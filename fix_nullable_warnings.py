#!/usr/bin/env python3
"""
Fix CS8602/CS8604 nullable warnings in ParserTests.cs by adding null-forgiving operator (!)
after variables that were checked with Assert.NotNull().

This script identifies patterns where:
1. A variable is cast with 'as' and then checked with Assert.NotNull
2. The variable is then dereferenced without using the ! operator

It adds the ! operator systematically.
"""

import re

def fix_nullable_warnings(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()

    # Track variables that have been null-checked in each test method
    # We'll look for patterns like:
    #   var foo = ... as FooType;
    #   Assert.NotNull(foo);
    #   // Use foo! for all following references
    #   ... foo.SomeProperty ... <- needs to become foo!.SomeProperty

    null_checked_vars = set()
    modified = False

    for i in range(len(lines)):
        line = lines[i]

        # Detect Assert.NotNull(variable)
        match = re.search(r'Assert\.NotNull\((\w+)\)', line)
        if match:
            null_checked_vars.add(match.group(1))
            continue

        # Reset null-checked variables at test method boundaries
        if re.match(r'\s*\[Fact', line) or re.match(r'\s*public (void|async Task)', line):
            null_checked_vars = set()
            continue

        # For each null-checked variable, add ! when it's dereferenced
        for var in null_checked_vars:
            # Pattern: var.Property or var.Method or var[index]
            # Replace with var!.Property or var!.Method or var![index]
            # But skip if already has !

            # Handle: var.Property or var.Method (but not var! already)
            pattern1 = rf'\b({var})\.([A-Z]\w+)'
            if re.search(pattern1, line) and f'{var}!' not in line:
                old_line = line
                line = re.sub(pattern1, r'\1!.\2', line)
                if line != old_line:
                    lines[i] = line
                    modified = True
                    print(f"Line {i+1}: Fixed {var}.Property -> {var}!.Property")

            # Handle: var[index] (but not var! already)
            pattern2 = rf'\b({var})\['
            if re.search(pattern2, line) and f'{var}!' not in line:
                old_line = line
                line = re.sub(pattern2, r'\1![', line)
                if line != old_line:
                    lines[i] = line
                    modified = True
                    print(f"Line {i+1}: Fixed {var}[index] -> {var}![index]")

    if modified:
        with open(file_path, 'w') as f:
            f.writelines(lines)
        print(f"\nSuccessfully fixed nullable warnings in {file_path}")
        return True
    else:
        print(f"No changes needed in {file_path}")
        return False

if __name__ == "__main__":
    import sys
    file_path = sys.argv[1] if len(sys.argv) > 1 else "tests/ParserTests.cs"
    fix_nullable_warnings(file_path)
