#!/bin/bash

#
# Print a number of lines to either stdout or stderr
# Args:
#   1: fd - 1 = stdout, 2 = stderr, 3 = both
#   2: count - number of lines to print
#   3: message - the message to print. It will be suffixed
#                with a counter message containing which 
#                line it is in the iteration.
#
print_to_fd() {
  for i in $(eval echo {1..$2}); do
    >&$1 echo "[$1]> $3: count=$i"
  done
}

if [[ "$1" == "1" || "$1" == "2" ]]; then
  print_to_fd $1 $2 $3
else
  print_to_fd 1 $2 $3
  print_to_fd 2 $2 $3
fi
