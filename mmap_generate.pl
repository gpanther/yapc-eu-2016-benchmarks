#!/usr/bin/perl
use Modern::Perl;
use autodie;
use PerlIO::gzip;
use Time::HiRes qw( time );
use Proc::ProcessTable;
use Storable;
use integer;

my %chrIdx;
$chrIdx{"$_"} = $_ for (1..22);
$chrIdx{"X"} = 23;
$chrIdx{"Y"} = 24;
$chrIdx{"MT"} = 25;

my $codec_context = createContext(4, 8);

my %nucleotide_map = (A => 0, C => 1, G => 2, T => 3);

my $start = time();
say 'Loading...';
open my $fin, '<:gzip', '/home/gpanther/Downloads/All_20160527_small.txt.gz';
my (@values, %long_values);
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
		push @values, [$key, $id];
	}
}
close $fin;

say 'Sorting...';
@values = sort { $a->[0] <=> $b->[0] } @values;


my $mask_bits = 20;
my $mask = 2**$mask_bits - 1;
my $shift = 64 - $mask_bits;
$shift -= 64 - getHighestBitSet($values[0]->[0] ^ $values[-1]->[0]);
my $max_items_per_bucket = 16;
say "Calculated shift: $shift";

say 'Writing...';
open my $fout, '>', 'values.obj';
binmode $fout;

my $filler = pack('QL', -1, -1);
my ($last_bucket, $items_in_bucket) = (0, 0);
for (@values) {
	my ($k, $v) = @$_;
	my $b = ($k >> $shift) & $mask;

	if ($b == $last_bucket) {
		$items_in_bucket += 1;
	} else {
		warn "Error! $items_in_bucket\n"
			unless $items_in_bucket <= $max_items_per_bucket;
		for (; $items_in_bucket < $max_items_per_bucket; ++$items_in_bucket) {
			print $fout $filler;
		}
		++$last_bucket;
		while ($last_bucket < $b) {
			for (1 .. $max_items_per_bucket) {
				print $fout $filler;
			}
			++$last_bucket;
		}
		$items_in_bucket = 1;

		say "$last_bucket / $mask";
	}

	print $fout pack('QL', $k, $v);
}

warn "Error2! $items_in_bucket\n"
	unless $items_in_bucket <= $max_items_per_bucket;
for (; $items_in_bucket < $max_items_per_bucket; ++$items_in_bucket) {
	print $fout $filler;
}
while ($last_bucket < $mask) {
	for (1 .. $max_items_per_bucket) {
		print $fout $filler;
	}
	++$last_bucket;
}
print $fout $filler;

close $fout;

say 'Writing long values...';
store \%long_values, 'long_values.obj';

my $end = time();
printf("Loaded in %.2f seconds\n", $end - $start);

foreach (@{Proc::ProcessTable->new()->table}) {
        next unless $_->pid eq $$;
	my $rss = $_->rss;
	$rss =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	say "RSS: $rss bytes";
	last;
}


sub getHighestBitSet {
	my $value = shift;
	for (reverse 0 .. 63) {
		return $_ if ($value & (1 << $_)) != 0;
	}
	return 0;
}

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

