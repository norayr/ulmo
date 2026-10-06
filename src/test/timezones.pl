#!/usr/bin/env perl
use strict;
use warnings;

sub header {
   my ($transitions, $types, $chars, $std) = @_;
   return "TZif\0" . ("\0" x 15) . pack("N6", 0, $std, 0, $transitions, $types, $chars);
}

sub save {
   my ($name, $data) = @_;
   open(my $out, ">", $name) or die "$name: $!";
   binmode($out);
   print {$out} $data or die "$name: $!";
   close($out) or die "$name: $!";
}

my $zone = header(2, 2, 8, 2) . pack("N2C2", 1000000, 2000000, 1, 0) .
   pack("NCCNCC", 14400, 0, 0, 18000, 1, 4) . "STD\0DST\0" . pack("C2", 1, 0);
save("long-zone-name", $zone);
save("negative-zone", header(0, 1, 4, 0) . pack("NCC", -3600, 0, 0) . "NEG\0");
save("unsigned-name", header(0, 1, 131, 0) . pack("NCC", 7200, 0, 128) . ("x" x 128) . "HI\0");
save("unsigned-type", header(1, 129, 4, 0) . pack("NC", 1000, 128) .
   (pack("NCC", 0, 0, 0) x 128) . pack("NCC", 14400, 0, 0) . "IDX\0");
substr($zone, 52, 1) = pack("C", 255);
save("bad-type", $zone);
save("bad-header", "not a timezone file");
