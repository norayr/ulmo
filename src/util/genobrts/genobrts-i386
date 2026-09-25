#!/usr/bin/env perl

use strict;
use warnings;
use Fcntl;
use IO::File;

my @rtmodules = qw(
   Coroutines
   Process
   RTErrors
   Storage
   SysArgs
   SysInterrupts
   SysModules
   SysSegments
);

my @unixmodules = qw(
   UnixClock
   UnixFiles
   UnixProcess
   UnixTimezones
);

my $sysmain = "SysMain";
my $sysstorage = "SysStorage";
my @allmodules = sort(@rtmodules, @unixmodules, $sysmain, $sysstorage);

my $cmdname = $0; $cmdname =~ s{.*/}{};
my $usage = "Usage: $cmdname (-r | [-o start.s] {module})\n";

my $outfile;
while (@ARGV > 0 && $ARGV[0] =~ m{^-}) {
   my $arg = shift @ARGV;
   last if $arg eq "--";
   if ($arg eq "-o") {
      die $usage if @ARGV == 0;
      $outfile = shift @ARGV;
   } elsif ($arg eq "-r") {
      foreach my $module (@allmodules) {
	 print $module, "\n";
      }
      exit 0;
   } else {
      die $usage;
   }
}
die $usage if @ARGV == 0;
my @core = @ARGV;

my $out;
if (defined $outfile) {
   $out = new IO::File $outfile, O_WRONLY|O_CREAT|O_TRUNC, 0666
      or die "$cmdname: unable to create $outfile: $!\n"
} else {
   $out = \*STDOUT;
}

my $HEADER = <<'END_OF_HEADER';
.global _rt__sigreturn
_rt__sigreturn:
	movl $0xad, %eax
	int $0x80
	nop
	xor %eax, %eax
	movl $0x0, (%eax)
.global _entry
_entry:
END_OF_HEADER

my $RTINIT = <<'END_OF_RTINIT';
	movl (%esp), %eax
	movl %eax, SysArgs_argc
	lea  4(%esp), %ebx
	movl %ebx, SysArgs_argv
	lea  4(%ebx, %eax, 4), %eax
	movl %eax, SysArgs_environ
envloop:
	cmpl $0, (%eax)
	je envend
	addl $4, %eax
	jmp envloop
envend:
	addl $4, %eax
	movl %eax, SysArgs_auxv
	xor %ebx, %ebx
	movl $45, %eax
	int $0x80
	mov %eax, %ebx
	addl $0x10ffff, %ebx
	andl $0xffff0000, %ebx
	movl $45, %eax
	int $0x80
	mov %eax, Storage_end
	movl $0x100000, Storage_left
END_OF_RTINIT

my $MEMINIT = <<'END_OF_MEMINIT';
	movl SysArgs_auxv,%ebx
	movl $0x1000,%esi
	movl $0x0, %edi
_auxvloop:
	cmpl $0x0,(%ebx)
	je _endauxvloop
	cmpl $0x21,(%ebx)
	jne _auxvbase
	movl 0x4(%ebx),%edi
	jmp _nextauxv
_auxvbase:
	cmpl $0x3,(%ebx)
	jne _nextauxv
	movl 0x4(%ebx),%esi
_nextauxv:
	addl $0x8,%ebx
	jmp _auxvloop
_endauxvloop:
	andl $0xfffff000, %esi
	cmpl $0x0,%esi
	jne _skip3
	movl $0x1000,%esi
_skip3:
	movl Storage_end, %eax
	subl $0x100000, %eax
	subl %esi, %eax
	pushl $0
	pushl %eax
	pushl %esi
	call SysSegments_Register
	movl $0,0x8(%esp)
	movl $0x10000,0x4(%esp)
	movl $0,(%esp)
	call SysSegments_Register
	movl Storage_end, %eax
	subl $0x100000, %eax
	movl $0x100000, 0x4(%esp)
	movl %eax, (%esp)
	movl $0, 0x8(%esp)
	call SysSegments_Register
	movl $-1, 0x8(%esp)
	movl %esp, %edx
	addl $0x0fffffff, %edx
	andl $0xf0000000, %edx
	movl %edx, %eax
	subl %esp, %eax
	andl $0xfffff000, %eax
	addl $0x00100000, %eax
	movl %eax, 0x4(%esp)
	movl %edx, (%esp)
	call SysSegments_Register
	orl %edx,%edx
	jz _skip
	movl $0, 0x8(%esp)
	movl %edx, (%esp)
	negl %edx
	movl %edx, 0x4(%esp)
	call SysSegments_Register
_skip:
	cmpl $0x0,%edi
	je _skip2
	cmpl %esp,%edi
	jae _skip2
	cmpl Storage_end,%esi
	jae _dosysinfo
	cmpl %esi,%edi
	jb _dosysinfo
	jmp _skip2
_dosysinfo:	
	movl $0x0,0x8(%esp)
	movl $0x1000,0x4(%esp)
	movl %edi,(%esp)
	call SysSegments_Register
_skip2:
	addl $0xc,%esp
	call SysStorage___init
	pushl $0
	movl %esp, %eax
	pushl $0
	pushl $0x10000
	pushl %eax
	call Storage_AllocateStack
	addl $0xc, %esp
	popl %eax
	pushl $0x10000
	pushl $0
	pushl %eax
	movl %esp, %ebx
	movl $0, %ecx
	movl $186, %eax
	int $0x80
	addl $0xc, %esp
END_OF_MEMINIT

my $EXIT = <<'END_OF_EXIT';
	call Process_Terminate
	hlt
END_OF_EXIT

sub call_startup {
   my ($out, $module) = @_;
   print $out "\tcall ${module}___startup\n";
}

sub call_init {
   my ($out, $module) = @_;
   print $out "\tcall ${module}___init\n";
}

print $out $HEADER;
foreach my $module (@rtmodules, @unixmodules, $sysstorage, $sysmain, @core) {
   call_startup($out, $module);
}
print $out $RTINIT;
foreach my $module (@rtmodules) {
   call_init($out, $module);
}
print $out $MEMINIT;
foreach my $module (@unixmodules, $sysmain) {
   call_init($out, $module);
}
print $out $EXIT;
$out->close or die "$cmdname: unable to finish output\n";
