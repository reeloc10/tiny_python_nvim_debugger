# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

import atexit
import json
import os
import queue
import runpy
import socket
import sys
import threading

if len(sys.argv) < 3:
    print("Usage: python3 tiny_debugger.py <nvim_pid> <target_script.py>")
    sys.exit(1)

nvim_pid = sys.argv[1]
target_file = sys.argv[2]

SOCKET_PATH = f"/dev/shm/tiny_debugger_{nvim_pid}.sock"
PY_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

@atexit.register
def cleanup_socket():
    if os.path.exists(SOCKET_PATH):
        try:
            os.unlink(SOCKET_PATH)
        except Exception:
            pass

class TinyDebugger:
    def __init__(self, target_file):
        cleanup_socket()

        self.target_file = os.path.abspath(target_file)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(SOCKET_PATH)
        self.server.listen(1)
        
        print(f"[Debugger] RAM socket active at {SOCKET_PATH}. Waiting for Neovim...")
        self.conn, _ = self.server.accept()
        print("[Debugger] Neovim connected! Waiting for start command and breakpoints...")
        
        self.rfile = self.conn.makefile('r')
        self.wfile = self.conn.makefile('w')
        
        self.command_queue = queue.Queue()
        self.lock = threading.Lock()
        self.verbose = False
        
        raw_msg = ""
        while not raw_msg:
            raw_msg = self.rfile.readline().strip()
            
        config = json.loads(raw_msg)

        # Enforce script dir check immediately on initial handshake
        self.check_script_dir(config.get("nvim_script_dir"))

        self.breakpoints = {}
        for bp in config.get("breakpoints", []):
            self.breakpoints[(os.path.abspath(bp["file"]), bp["line"])] = bp.get("hits", 0)
            
        self.verbose = config.get("verbose", False)

        self.step_mode = "continue"
        self.stop_frame = None

        self.listener_thread = threading.Thread(target=self._socket_listener, daemon=True)
        self.listener_thread.start()
        
        print(f"[Debugger] Loaded {len(self.breakpoints)} breakpoint(s). Execution starting...")

    def check_script_dir(self, nvim_script_dir):
        norm_py = os.path.realpath(PY_SCRIPT_DIR)
        norm_nvim = os.path.realpath(nvim_script_dir) if nvim_script_dir else ""
        if not norm_nvim or norm_py != norm_nvim:
            msg = (
                f"Fatal Script Location Mismatch! Python tiny_debugger.py is in '{norm_py}' "
                f"but Neovim tiny_debugger.lua is in '{norm_nvim or 'UNKNOWN'}'. Aborting for stability."
            )
            print(f"[Debugger Error] {msg}")
            self.send_event({"event": "fatal_error", "message": msg})
            os._exit(1)

    def _socket_listener(self):
        try:
            while True:
                line = self.rfile.readline()
                if not line:
                    break
                cmd_str = line.strip()
                if cmd_str:
                    try:
                        data = json.loads(cmd_str)
                        if isinstance(data, dict):
                            self.verbose = data.get("verbose", self.verbose)
                            self.check_script_dir(data.get("nvim_script_dir"))

                            cmd = data.get("command")
                            if cmd == "quit":
                                print("[Debugger] Termination requested by Neovim. Exiting...")
                                os._exit(0)
                            elif cmd == "reset_breakpoints":
                                with self.lock:
                                    self.breakpoints = {}
                                print("[Debugger] Breakpoints reset.")
                            elif cmd == "continue":
                                new_bps = {}
                                for bp in data.get("breakpoints", []):
                                    key = (os.path.abspath(bp["file"]), bp["line"])
                                    new_bps[key] = bp.get("hits", 0)
                                with self.lock:
                                    self.breakpoints = new_bps
                                self.command_queue.put("continue")
                            elif cmd and cmd.startswith("eval:"):
                                self.command_queue.put(cmd)
                            elif cmd:
                                self.command_queue.put(cmd)
                    except json.JSONDecodeError:
                        self.command_queue.put(cmd_str)
        except Exception as e:
            print(f"[Debugger Listener Error]: {e}")

    def send_event(self, data):
        with self.lock:
            self.wfile.write(json.dumps(data) + "\n")
            self.wfile.flush()

    def trace_calls(self, frame, event, arg):
        if event == 'call':
            filename = frame.f_code.co_filename
            if filename.startswith("<frozen"):
                return None
            if self.step_mode == "next" and frame.f_back is self.stop_frame:
                return None
            return self.trace_lines
        return None

    def trace_lines(self, frame, event, arg):
        if event == 'line':
            filename = os.path.abspath(frame.f_code.co_filename)
            lineno = frame.f_lineno

            if self.verbose and filename == self.target_file:
                print(f"[Trace] Visiting {filename}:{lineno}")
                self.send_event({"event": "trace", "file": filename, "line": lineno})

            should_stop = False
            bp_key = (filename, lineno)

            if self.step_mode == "continue":
                with self.lock:
                    current_bps = self.breakpoints
                if bp_key in current_bps:
                    should_stop = True
            elif self.step_mode == "next":
                if frame is self.stop_frame:
                    should_stop = True
                elif self.stop_frame:
                    in_stack = False
                    curr = frame
                    while curr:
                        if curr is self.stop_frame:
                            in_stack = True
                            break
                        curr = curr.f_back
                    if not in_stack:
                        self.stop_frame = frame
                        should_stop = True
            elif self.step_mode == "step":
                should_stop = True

            if should_stop:
                with self.lock:
                    if bp_key in self.breakpoints:
                        self.breakpoints[bp_key] += 1
                        current_hits = self.breakpoints[bp_key]
                    else:
                        current_hits = 1

                self.step_mode = "paused"
                self.send_event({
                    "event": "stopped",
                    "file": filename,
                    "line": lineno,
                    "hits": current_hits
                })

                while True:
                    cmd = self.command_queue.get()
                    
                    if cmd.startswith("eval:"):
                        expr = cmd[5:]
                        try:
                            safe_builtins = {
                                'abs': abs, 'len': len, 'range': range, 'str': str,
                                'int': int, 'float': float, 'list': list, 'dict': dict,
                                'set': set, 'tuple': tuple, 'bool': bool, 'round': round
                            }
                            val = eval(expr, {"__builtins__": safe_builtins}, {**frame.f_globals, **frame.f_locals})
                            res = str(val)
                        except Exception as e:
                            res = f"Error: {e!s}"
                        self.send_event({"event": "eval_result", "expr": expr, "result": res})
                    
                    elif cmd == "stack":
                        stack_frames = []
                        curr = frame
                        while curr:
                            stack_frames.append({
                                "file": os.path.abspath(curr.f_code.co_filename),
                                "name": curr.f_code.co_name,
                                "line": curr.f_lineno
                            })
                            curr = curr.f_back
                        self.send_event({"event": "stack_result", "stack": stack_frames})

                    elif cmd == 'continue':
                        self.step_mode = 'continue'
                        break
                    elif cmd == 'next':
                        self.step_mode = 'next'
                        self.stop_frame = frame
                        break
                    elif cmd == 'step':
                        self.step_mode = 'step'
                        break

        return self.trace_lines

def attach(target_file):
    debugger = TinyDebugger(target_file)
    sys.settrace(debugger.trace_calls)

if __name__ == "__main__":
    if not os.path.exists(target_file):
        print(f"Error: Target file '{target_file}' not found.")
        sys.exit(1)

    # Shift out tiny_debugger.py and nvim_pid, making target_file sys.argv[0] for the target script
    sys.argv = sys.argv[2:]
    sys.path.insert(0, os.path.dirname(os.path.abspath(target_file)))

    attach(target_file)
    try:
        runpy.run_path(target_file, run_name="__main__")
    except Exception as e:
        print(f"[Debugger] Target error: {e}")
