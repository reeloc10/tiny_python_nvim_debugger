# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 reeloc10

import inner

def main():
    # __import__('os').system('echo "hacked"')
    # exec("print('test')")
    # open('/etc/passwd').read()

    print("Starting execution...", flush=True)
    x = 10
    y = 20
    z = x + y
    print(f"Result computed: {z}", flush=True)

if __name__ == "__main__":
    main()
