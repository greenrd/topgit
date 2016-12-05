#!/usr/bin/env bats

sed_test_01() {
    echo "refs/heads/t/hcbsd/11/optimized-kernels" | sed -r 's#^refs/(heads|top-bases)/##'
}

@test "system sed supports -r option" {
    run sed_test_01 ""
    [ $status -eq 0 ]
    [ "${lines[0]}" = "t/hcbsd/11/optimized-kernels" ]
}
