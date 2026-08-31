# Phase 1 Documentation

You will find the documentation and problem descriptions for phase one in `phase_1/documentation/phase_1.pdf`. Be sure to **read all pages** of the PDF. There are two parts to this phase, that break down as follows.

1. RISC-V Assembly

    1.1 Multiplication

    1.2 General Matrix Multiplication

    1.3 Sobel Filter
    
2. RISC-V Assembler

# Phase 1 self-check

This docker file exists to aid students in validating their phase 1 results before submitting for a grade.

This does not include all test cases, and it is up to the students to fully validate the functionality of their code.

Either a linux environment or docker is required.

## Put your files here

```
phase_1/submission/
    assembler.py
    addition.s
    gemm.s
    mult.s
    sobel.s
```

## Run it with Docker

Build once only the first time:

```
docker build -t phase1-check phase_1
```

Then run after first build or after editing:

```
docker run --rm -v "$PWD/phase_1/submission:/work/submission" phase_1-check:latest
```

## Run it without Docker

Needs `python3` and `java` on your PATH:

```
./phase_1/run_test.sh mycheck
```

Pass a directory as a second argument to check files kept somewhere other than
`phase_1/submission/`.

## Reading the output

One line per check, then a total:

```
PASS  Assembly:  gemm (config 1)
FAIL  Assembly:  mult (config 1)  --  result memory differs from the expected ...
...
8/9 PASS
```

A FAIL line ends with the reason. The command exits 0 only when all nine pass.

Outside Docker, the summary is also written to `phase_1/results/<name>.txt`, and
what each check produced -- the program it ran, the RARS memory dump, and the
files your assembler generated -- is left in `phase_1/output/` for you to
inspect.
