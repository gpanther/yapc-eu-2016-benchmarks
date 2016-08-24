#!/usr/bin/perl
use Modern::Perl;
use autodie;
use PerlIO::gzip;
use Time::HiRes qw( time );
use Proc::ProcessTable;
use Sys::Mmap;
use Storable qw( retrieve );
use integer;
use Inline C => Config =>
   BUILD_NOISY => 1;

my %chrIdx;
$chrIdx{"$_"} = $_ for (1..22);
$chrIdx{"X"} = 23;
$chrIdx{"Y"} = 24;
$chrIdx{"MT"} = 25;

my $codec_context = createContext(4, 8);

my %nucleotide_map = (A => 0, C => 1, G => 2, T => 3);

my $start = time();
my $long_values = retrieve('long_values.obj');
my $values;
open my $fin, '<', 'values.obj';
binmode $fin;
my $mmaped_addr = mmap($values, 0, PROT_READ, MAP_SHARED, $fin);
my $end = time();

printf("Loaded in %.2f seconds\n", $end - $start);

use Inline C => << '...';
#include <stdint.h>

#define MASK_BITS 20
#define MASK ((1 << MASK_BITS) - 1)
#define SHIFT 43
#define MAX_ITEMS_PER_BUCKET 16
#define BUCKET_SIZE (MAX_ITEMS_PER_BUCKET * 12)

int getValueAt(SV *sv_base_addr, SV *sv_key) {
	int64_t key = SvIV(sv_key);
	int64_t m = (key >> SHIFT) & MASK;
	int64_t base_addr = SvIV(sv_base_addr);

	void *ss = (void*)(base_addr + m*BUCKET_SIZE);
	void *se = ss + BUCKET_SIZE;
	while (ss < se) {
		int64_t *k = (int64_t*)ss;
		if (*k == key) { return 1; }
		ss += 12;
	}
        return 0;
}
...


foreach (@{Proc::ProcessTable->new()->table}) {
        next unless $_->pid eq $$;
	my $rss = $_->rss;
	$rss =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
	say "RSS: $rss bytes";
	last;
}


my $mask_bits = 20;
my $mask = 2**$mask_bits - 1;
my $shift = 43;
my $max_items_per_bucket = 16;
my $bucket_size = $max_items_per_bucket * 12;

$start = time();

my $ri = getIndex([$nucleotide_map{'C'}], $codec_context) << 18;
my $ai = getIndex([$nucleotide_map{'T'}], $codec_context) << 1;
my ($found, $not_found) = (0, 0);
for my $chr ((1..22, 'X', 'Y', 'MT')) {
	say $chr;
	my $chri = $chrIdx{$chr} << 59;

	for my $pos (1_000..500_000) {
		$pos *= 2;
		my $key = $chri | ($pos << 35) | $ri | $ai;
		if (getValueAt($mmaped_addr, $key)) { ++$found; } else { ++$not_found; }
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

