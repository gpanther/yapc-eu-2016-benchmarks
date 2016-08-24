#!/usr/bin/perl
use Modern::Perl;
use autodie;
use PerlIO::gzip;
use Time::HiRes qw( time );
use Proc::ProcessTable;
use integer;

my %chrIdx;
$chrIdx{"$_"} = $_ for (1..22);
$chrIdx{"X"} = 23;
$chrIdx{"Y"} = 24;
$chrIdx{"MT"} = 25;

my $codec_context = createContext(4, 8);

my %nucleotide_map = (A => 0, C => 1, G => 2, T => 3);

my $start = time();
open my $fin, '<:gzip', '/home/gpanther/Downloads/All_20160527_small.txt.gz';
my (%values, %long_values);
while (<$fin>) {
	chomp;
	my ($chr, $pos, $id, $ref, $alt) = split /\t/;

	$pos = int($pos);
	$id = int(substr($id, 2));

	if ($ref !~ /^[ACGT]{0,8}$/ || $alt !~ /^[ACGT]{0,8}$/) {
		my $key = "$chr|$pos|$ref|$alt";
		$long_values{$key} = $id;
	}
	else {
		$chr = $chrIdx{$chr};

		my @ref = map { $nucleotide_map{$_} } split //, $ref;
		my @alt = map { $nucleotide_map{$_} } split //, $alt;

		my $ri = getIndex(\@ref, $codec_context);
		my $ai = getIndex(\@alt, $codec_context);

		my $key = ($chr << 59) | ($pos << 35) | ($ri << 18) | ($ai << 1);
		$values{$key} = $id;
	}
}
my $end = time();
close $fin;

printf("Loaded in %.2f seconds\n", $end - $start);

foreach (@{Proc::ProcessTable->new()->table}) {
        next unless $_->pid eq $$;
	my $rss = $_->rss;
	$rss =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	say "RSS: $rss bytes";
	last;
}


$start = time();

my $ri = getIndex([$nucleotide_map{'C'}], $codec_context) << 18;
my $ai = getIndex([$nucleotide_map{'T'}], $codec_context) << 1;
my ($found, $not_found) = (0, 0);
for my $chr ((1..22, 'X', 'Y', 'MT')) {
	say "$chr";
	my $chri = $chrIdx{$chr} << 59;

	for my $pos (1_000..500_000) {
		$pos *= 2;
		my $key = $chri | ($pos << 35) | $ri | $ai;
		if (exists $values{$key}) {
			$found += 1;
		} else {
			$not_found += 1;
		}
	}
}
$end = time();

printf("Verified in %.2f seconds. Found: %d, not found: %d\n", $end - $start, $found, $not_found);


sub createContext {
        my ($alphabet_size, $max_len) = @_;
        my $result = {
                alphabet_size => $alphabet_size,
                max_len => $max_len,
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

