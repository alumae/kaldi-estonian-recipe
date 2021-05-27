#!/bin/bash
# Creates a simple token-based language model from tokenized text.
# 
# This assumes that one has installed OpenFst and OpenGrm-NGram and that
# that their binaries are in the user's $PATH.
#
# Sample usages:
#
#     ./make_chatspeak_lm /tmp/earnest.txt /tmp/earnest.fst
#     ./make_chatspeak_lm -m kneser_ney -o 6 /tmp/earnest.txt /tmp/earnest.fst

set -eou pipefail

METHOD="witten_bell"
ORDER="3"

while getopts m:o: NAME; do
    case ${NAME} in
      m)    METHOD="${OPTARG}";;
      o)    ORDER="${OPTARG}";;
      ?)    printf "Usage: %s: [-m method] [-o order] args\n" "$0"
            exit 2;;
    esac
done
shift "$((OPTIND-1))"

readonly CORPUS="$1"
readonly OUTPUT="$2"
readonly TMPDIR="`dirname $2`"
readonly FLD="${TMPDIR}/fld"
readonly SYM="${TMPDIR}/sym"
readonly FAR="${TMPDIR}/far"
readonly CNT="${TMPDIR}/cnt"
readonly FST="${TMPDIR}/fst"

casefold() {
    echo -n "Splitting to characters..."
    # This assumes ASCII inputs; it will not casefold non-ASCII codepoints.
    #tr [:upper:] [:lower:] < "${CORPUS}" > "${FLD}"
    perl -CSAD -npe 'use utf8; s/(\S)/\1 /g' < "${CORPUS}" > "${FLD}"
    echo "done."
}

symbols() {
    echo -n "Generating symbol table..."
    ngramsymbols "${FLD}" "${SYM}"
    echo "done."
}

far() {
    echo -n "Compiling FAR..."
    farcompilestrings \
        --fst_type=compact \
        --symbols="${SYM}" \
        --keep_symbols \
        "${FLD}" \
        "${FAR}"
    echo "done."
}

count() {
    echo -n "Collecting counts..."
    ngramcount \
        --order="${ORDER}" \
        "${FAR}" \
        "${CNT}"
    echo "done."
}

make() {
    echo -n "Smoothing model..."
    ngrammake \
        --method="${METHOD}" \
        "${CNT}" \
        "${FST}"
    echo "done."
}

clean() {
    echo -n "Cleaning up..."
    mv "${FST}" "${OUTPUT}"
    #rm -rf "${TMPDIR}"
    echo "done."
    echo "Output FST: ${OUTPUT}"
}

main() {
   casefold
   symbols
   far
   count
   make
   clean
}

main
