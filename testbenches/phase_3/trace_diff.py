def is_dont_care(val):
    """Check if a value is a don't-care (contains x or X)"""
    # this assumes the entire value is a don't-care
    # i.e. it will mess up on outputs like 0000xxxx
    return 'x' in val.lower()

def values_match(generated, expected):
    """Check if values match, accounting for don't-cares"""
    if is_dont_care(expected):
        return True
    return generated.lower() == expected.lower()

# TODO: allow for input of trace files as command line args
with open("generated.trace") as gen, open("expected.trace") as exp:
    # Strip comments and empty lines
    # stripping gen lets us leave comments in our trace
    gen_lines = [line.strip() for line in gen 
                 if line.strip() and not line.strip().startswith('#')]
    exp_lines = [line.strip() for line in exp 
                 if line.strip() and not line.strip().startswith('#')]
    
    for i, (g, e) in enumerate(zip(gen_lines, exp_lines)):
        gen_fields = g.split()
        exp_fields = e.split()
        
        # Compare each field
        for j, (gf, ef) in enumerate(zip(gen_fields, exp_fields)):
            if not values_match(gf, ef):
                print(f"Line {i}, Field {j}: Value mismatch")
                print(f"Got:      {g}")
                print(f"Expected: {e}")
                exit(1)  # Quit after first failure
    
    print("PASS!")
