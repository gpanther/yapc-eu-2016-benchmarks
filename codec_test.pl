#!/usr/bin/perl
use Modern::Perl;
use experimental 'smartmatch';
use DDP;

my ($max_len, $alphabet_size) = (3, 4);
my $context = createContext($alphabet_size, $max_len);

for my $idx (0 .. scalar(@{$context->{dictionary}}) - 1) {
	my $word = $context->{dictionary}->[$idx];

	my $get_index_result = getIndex($word, $context);
	die "Expected $idx but was $get_index_result\n"
		unless $get_index_result == $idx;
	my $get_word_result = getWord($idx, $context);
	die "Expected @{$word} but was @{$get_word_result}\n"
		unless @$get_word_result ~~ @$word;

	say "$idx ok";
}

sub genPerm {
	my ($max_len, $alphabet_size) = @_;
	my $result = [];
	genPermImpl($result, [], $max_len, $alphabet_size);
	return $result;
}

sub genPermImpl {
	my ($accumulator_ref, $prefix, $max_len, $alphabet_size) = @_;

	push @$accumulator_ref, $prefix;
	return if scalar(@$prefix) == $max_len;

	for my $next_element (1 .. $alphabet_size) {
		my $new_prefix = [@$prefix, $next_element];
		genPermImpl($accumulator_ref, $new_prefix, $max_len, $alphabet_size);
	}
}

sub createContext {
	my ($alphabet_size, $max_len) = @_;
	my $result = {
		alphabet_size => $alphabet_size,
		max_len => $max_len,
		dictionary => genPerm($max_len, $alphabet_size), 
	};

	my $exact_count = [];
	for (0 .. $max_len) {
		push @$exact_count, $alphabet_size ** $_;
	}
	$result->{'exact_count'} = $exact_count;

	my $total_count = [$exact_count->[0]];
	for (1 .. $max_len) {
		push @$total_count, $total_count->[$_ - 1] + $exact_count->[$_];
	}
	$result->{'total_count'} = $total_count;

	return $result;
}

sub getIndex {
	my ($word, $context) = @_;

	my $result = 0;
	for my $len (1 .. $context->{'max_len'}) {
		$result += getNoWordsLtOrEqWithLen($word, $len, $context);
	}

	return $result;
}

sub getNoWordsLtOrEqWithLen {
	my ($word, $len, $context) = @_;

	my $word_len = scalar(@$word);
	return 0 if $word_len == 0;

	my $first_char = $word->[0];
	return $first_char if $len == 1;

	my $result = ($first_char - 1) * $context->{exact_count}->[$len - 1];
	my @shorter_word = @$word;
	shift @shorter_word;
	$result += getNoWordsLtOrEqWithLen(\@shorter_word, $len - 1, $context);
	return $result;
}

sub getWord {
	my ($idx, $context) = @_;

	# TODO - probably this: http://math.stackexchange.com/a/195739/204101
	return $context->{dictionary}->[$idx];
}

