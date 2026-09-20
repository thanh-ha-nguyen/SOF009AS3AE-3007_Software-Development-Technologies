#!/bin/bash

# The https://github.com/hugovk/everyfinnishword GitHub repository contains a plaintext file
# with a list of Finnish words, which can be used to create the word lists for Sanuli.
# See the repository for more information and the license terms. The repository is maintained
# by Hugo van Kemenade, and it is not affiliated with Kotus, Sanuli or the authors of this exercise.

# The URL of the word list file in the GitHub repository:
URL="https://raw.githubusercontent.com/hugovk/everyfinnishword/refs/heads/master/kaikkisanat.txt"

# Fetch the word list from the URL, then pipe (|) the output through
# a series of commands to process it, before saving the result to a file.
echo "Fetching word list from $URL"
curl --silent --show-error $URL |

    # filter lines that are exactly 5 characters long and contain only letters a-z:
    grep -E '^[a-zA-Z]{5}$' |

    # convert all words to uppercase
    tr '[:lower:]' '[:upper:]' |

    # remove duplicates and save the output in full-words.txt
    uniq > full-words.txt


# check if the command succeeded to create the file
if [ ! -s full-words.txt ]; then
    echo "Warning: full-words.txt is empty"
fi


# copy the same file to the other word lists:
echo "Creating other word list files as copies of full-words.txt"

# these word files are required, but not always used in the game:
cp full-words.txt common-words.txt
cp full-words.txt daily-words.txt
cp full-words.txt easy-words.txt

# a blacklist of profanities is required, but in this case an empty file is sufficient:
touch profanities.txt