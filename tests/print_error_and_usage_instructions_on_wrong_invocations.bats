#!/usr/bin/env bats

@test "print error and usage instructions on wrong invocations" {
  local -A options
  options["-c"]=value
  options["-X"]=invalid
  options["-o foo -o bar"]="multiple times"

  shopt -s nocasematch
  for option in "${!options[@]}"; do
    # shellcheck disable=2086
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" ${option}
    ((status != 0))
    [[ ${lines[0]} =~ ${options["${option}"]} ]]
    [[ ${lines[*]:1} =~ Usage: ]]
  done
}
