#!/bin/sh

test_description='git praise textconv support'
. ./test-lib.sh

find_praise() {
	sed -e 's/^[^(]*//'
}

cat >helper <<'EOF'
#!/bin/sh
grep -q '^bin: ' "$1" || { echo "E: $1 is not \"binary\" file" 1>&2; exit 1; }
"$PERL_PATH" -p -e 's/^bin: /converted: /' "$1"
EOF
chmod +x helper

test_expect_success 'setup ' '
	echo "bin: test number 0" >zero.bin &&
	echo "bin: test 1" >one.bin &&
	echo "bin: test number 2" >two.bin &&
	test_ln_s_add one.bin symlink.bin &&
	git add . &&
	GIT_AUTHOR_NAME=Number1 git commit -a -m First --date="2010-01-01 18:00:00" &&
	echo "bin: test 1 version 2" >one.bin &&
	echo "bin: test number 2 version 2" >>two.bin &&
	rm -f symlink.bin &&
	test_ln_s_add two.bin symlink.bin &&
	GIT_AUTHOR_NAME=Number2 git commit -a -m Second --date="2010-01-01 20:00:00"
'

cat >expected <<EOF
(Number2 2010-01-01 20:00:00 +0000 1) bin: test 1 version 2
EOF

test_expect_success 'no filter specified' '
	git praise one.bin >praise &&
	find_praise Number2 <praise >result &&
	test_cmp expected result
'

test_expect_success 'setup textconv filters' '
	echo "*.bin diff=test" >.gitattributes &&
	echo "zero.bin eol=crlf" >>.gitattributes &&
	git config diff.test.textconv ./helper &&
	git config diff.test.cachetextconv false
'

test_expect_success 'praise with --no-textconv' '
	git praise --no-textconv one.bin >praise &&
	find_praise <praise> result &&
	test_cmp expected result
'

cat >expected <<EOF
(Number2 2010-01-01 20:00:00 +0000 1) converted: test 1 version 2
EOF

test_expect_success 'basic praise on last commit' '
	git praise one.bin >praise &&
	find_praise  <praise >result &&
	test_cmp expected result
'

cat >expected <<EOF
(Number1 2010-01-01 18:00:00 +0000 1) converted: test number 2
(Number2 2010-01-01 20:00:00 +0000 2) converted: test number 2 version 2
EOF

test_expect_success 'praise --textconv going through revisions' '
	git praise --textconv two.bin >praise &&
	find_praise <praise >result &&
	test_cmp expected result
'

test_expect_success 'praise --textconv with local changes' '
	test_when_finished "git checkout zero.bin" &&
	printf "bin: updated number 0\015" >zero.bin &&
	git praise --textconv zero.bin >praise &&
	expect="(Not Committed Yet ....-..-.. ..:..:.. +0000 1)" &&
	expect="$expect converted: updated number 0" &&
	expr "$(find_praise <praise)" : "^$expect"
'

test_expect_success 'setup +cachetextconv' '
	git config diff.test.cachetextconv true
'

cat >expected_one <<EOF
(Number2 2010-01-01 20:00:00 +0000 1) converted: test 1 version 2
EOF

test_expect_success 'praise --textconv works with textconvcache' '
	git praise --textconv two.bin >praise &&
	find_praise <praise >result &&
	test_cmp expected result &&
	git praise --textconv one.bin >praise &&
	find_praise  <praise >result &&
	test_cmp expected_one result
'

test_expect_success 'setup -cachetextconv' '
	git config diff.test.cachetextconv false
'

test_expect_success 'make a new commit' '
	echo "bin: test number 2 version 3" >>two.bin &&
	GIT_AUTHOR_NAME=Number3 git commit -a -m Third --date="2010-01-01 22:00:00"
'

test_expect_success 'praise from previous revision' '
	git praise HEAD^ two.bin >praise &&
	find_praise <praise >result &&
	test_cmp expected result
'

cat >expected <<EOF
(Number2 2010-01-01 20:00:00 +0000 1) two.bin
EOF

test_expect_success SYMLINKS 'praise with --no-textconv (on symlink)' '
	git praise --no-textconv symlink.bin >praise &&
	find_praise <praise >result &&
	test_cmp expected result
'

test_expect_success SYMLINKS 'praise --textconv (on symlink)' '
	git praise --textconv symlink.bin >praise &&
	find_praise <praise >result &&
	test_cmp expected result
'

# cp two.bin three.bin  and make small tweak
# (this will direct praise -C -C three.bin to consider two.bin and symlink.bin)
test_expect_success 'make another new commit' '
	cat >three.bin <<\EOF &&
bin: test number 2
bin: test number 2 version 2
bin: test number 2 version 3
bin: test number 3
EOF
	git add three.bin &&
	GIT_AUTHOR_NAME=Number4 git commit -a -m Fourth --date="2010-01-01 23:00:00"
'

test_expect_success 'praise on last commit (-C -C, symlink)' '
	git praise -C -C three.bin >praise &&
	find_praise <praise >result &&
	cat >expected <<\EOF &&
(Number1 2010-01-01 18:00:00 +0000 1) converted: test number 2
(Number2 2010-01-01 20:00:00 +0000 2) converted: test number 2 version 2
(Number3 2010-01-01 22:00:00 +0000 3) converted: test number 2 version 3
(Number4 2010-01-01 23:00:00 +0000 4) converted: test number 3
EOF
	test_cmp expected result
'

test_done
