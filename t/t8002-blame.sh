#!/bin/sh

test_description='git praise'
. ./test-lib.sh

PROG='git praise -c'
. "$TEST_DIRECTORY"/annotate-tests.sh

PROG='git praise -c -e'
test_expect_success 'praise --show-email' '
	check_count \
		"<A@test.git>" 1 \
		"<B@test.git>" 1 \
		"<B1@test.git>" 1 \
		"<B2@test.git>" 1 \
		"<author@example.com>" 1 \
		"<C@test.git>" 1 \
		"<D@test.git>" 1 \
		"<E at test dot git>" 1
'

test_expect_success 'setup showEmail tests' '
	echo "bin: test number 1" >one &&
	git add one &&
	GIT_AUTHOR_NAME=name1 \
	GIT_AUTHOR_EMAIL=email1@test.git \
	git commit -m First --date="2010-01-01 01:00:00" &&
	cat >expected_n <<-\EOF &&
	(name1 2010-01-01 01:00:00 +0000 1) bin: test number 1
	EOF
	cat >expected_e <<-\EOF
	(<email1@test.git> 2010-01-01 01:00:00 +0000 1) bin: test number 1
	EOF
'

find_praise () {
	sed -e 's/^[^(]*//'
}

test_expect_success 'praise with no options and no config' '
	git praise one >praise &&
	find_praise <praise >result &&
	test_cmp expected_n result
'

test_expect_success 'praise with showemail options' '
	git praise --show-email one >praise1 &&
	find_praise <praise1 >result &&
	test_cmp expected_e result &&
	git praise -e one >praise2 &&
	find_praise <praise2 >result &&
	test_cmp expected_e result &&
	git praise --no-show-email one >praise3 &&
	find_praise <praise3 >result &&
	test_cmp expected_n result
'

test_expect_success 'praise with showEmail config false' '
	git config praise.showEmail false &&
	git praise one >praise1 &&
	find_praise <praise1 >result &&
	test_cmp expected_n result &&
	git praise --show-email one >praise2 &&
	find_praise <praise2 >result &&
	test_cmp expected_e result &&
	git praise -e one >praise3 &&
	find_praise <praise3 >result &&
	test_cmp expected_e result &&
	git praise --no-show-email one >praise4 &&
	find_praise <praise4 >result &&
	test_cmp expected_n result
'

test_expect_success 'praise with showEmail config true' '
	git config praise.showEmail true &&
	git praise one >praise1 &&
	find_praise <praise1 >result &&
	test_cmp expected_e result &&
	git praise --no-show-email one >praise2 &&
	find_praise <praise2 >result &&
	test_cmp expected_n result
'

test_done
