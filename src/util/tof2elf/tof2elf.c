/* Ulm's Oberon Compiler
   Copyright (C) 1989-2004 by University of Ulm, SAI, D-89069 Ulm, Germany
   ----------------------------------------------------------------------------
   Ulm's Oberon Library is free software; you can redistribute it
   and/or modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either version
   2 of the License, or (at your option) any later version.

   Ulm's Oberon Library is distributed in the hope that it will be
   useful, but WITHOUT ANY WARRANTY; without even the implied warranty
   of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   ----------------------------------------------------------------------------
   E-mail contact: oberon@mathematik.uni-ulm.de
   ----------------------------------------------------------------------------
   $Id: tof2elf.c,v 1.1 2004/09/07 12:57:03 borchert Exp borchert $
   ----------------------------------------------------------------------------
   $Log: tof2elf.c,v $
   Revision 1.1  2004/09/07 12:57:03  borchert
   Initial revision

   ----------------------------------------------------------------------------
*/

/* Original author: Christian Ehrhardt */

/* Fix by Norayr Chilingarian for modern libelf:
   We're now using single Elf_Data buffer per section
   instead of one Elf_Data per item.
   Old libelf respected user-set d_off;
   modern elfutils ignores it and recomputes offsets during elf_update(),
   causing sh_name/symbol-index mismatches in the original multi-chunk code. */

/* AMD64 (ELF64) support: dual i386/amd64 target via -arch flag. */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <libelf.h>
#include <elf.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

#define BUG(X) do { fprintf(stderr, "%s: input format error %d\n", cmdname, (X)); exit(1); } while (0);
#define UNEXPECTED_EOF do { fprintf(stderr, "%s: unexpected EOF in input\n", cmdname); exit(1); } while (0);

#define R_386_32       1
#define R_386_GLOB_DAT 6
#define R_X86_64_64    1
#define R_X86_64_32    10
#define R_X86_64_GLOB_DAT 6

static int is64 = 0;   /* 0 = i386/ELF32, 1 = amd64/ELF64 */

/*
 * String table - single growable buffer, one Elf_Data for the whole section.
 * newstr() appends to strbuf and keeps strdata->d_buf/d_size current.
 * The returned offset is the byte position within the section, suitable
 * for use as sh_name / st_name.
 */
static Elf_Scn  *strscn  = NULL;
static Elf_Data *strdata = NULL;
static char     *strbuf  = NULL;
static size_t    strused = 0;
static size_t    stralloc = 0;

static size_t newstr(const char *s) {
  size_t len = strlen(s) + 1;
  size_t ret = strused;

  if (strused + len > stralloc) {
    stralloc = (strused + len + 1023) & ~(size_t)1023;
    strbuf = realloc(strbuf, stralloc);
    if (!strbuf) { perror("realloc"); exit(1); }
  }
  memcpy(strbuf + strused, s, len);
  strused += len;

  if (!strdata) {
    strdata = elf_newdata(strscn);
    strdata->d_type    = ELF_T_BYTE;
    strdata->d_align   = 1;
    strdata->d_off     = 0;
    strdata->d_version = EV_CURRENT;
  }
  /* Always refresh the pointer in case realloc moved the buffer. */
  strdata->d_buf  = strbuf;
  strdata->d_size = strused;

  return ret;
}

/*
 * Symbol table - single growable array of Elf32_Sym or Elf64_Sym, one Elf_Data.
 * newsym() appends an entry and returns the zero-based symbol index.
 */
static Elf_Scn   *symscn   = NULL;
static Elf_Data  *symdata  = NULL;
static void      *symbuf   = NULL;
static int        symcount = 0;
static int        symalloc = 0;

static int newsym(size_t name_off, int section, int value) {
  int ret = symcount;
  size_t esz = is64 ? sizeof(Elf64_Sym) : sizeof(Elf32_Sym);

  if (symcount >= symalloc) {
    symalloc = symalloc ? symalloc * 2 : 16;
    symbuf = realloc(symbuf, symalloc * esz);
    if (!symbuf) { perror("realloc"); exit(1); }
  }

  if (is64) {
    Elf64_Sym *sym = (Elf64_Sym *)symbuf + symcount;
    sym->st_name  = name_off;
    sym->st_value = value;
    sym->st_size  = 0;
    sym->st_info  = ELF64_ST_INFO(STB_GLOBAL, STT_OBJECT);
    sym->st_other = 0;
    sym->st_shndx = section;
  } else {
    Elf32_Sym *sym = (Elf32_Sym *)symbuf + symcount;
    sym->st_name  = name_off;
    sym->st_value = value;
    sym->st_size  = 0;
    sym->st_info  = ELF32_ST_INFO(STB_GLOBAL, STT_OBJECT);
    sym->st_other = 0;
    sym->st_shndx = section;
  }
  symcount++;

  if (!symdata) {
    symdata = elf_newdata(symscn);
    symdata->d_type    = ELF_T_SYM;
    symdata->d_align   = is64 ? 8 : 4;
    symdata->d_off     = 0;
    symdata->d_version = EV_CURRENT;
  }
  symdata->d_buf  = symbuf;
  symdata->d_size = symcount * esz;

  return ret;
}

/*
 * Section header helpers - arch-aware wrappers.
 */
static void sh_set(Elf_Scn *scn, size_t name_off, int type, int flags,
                   int link, int info, int entsize) {
  if (is64) {
    Elf64_Shdr *shdr = elf64_getshdr(scn);
    shdr->sh_name    = name_off;
    shdr->sh_type    = type;
    shdr->sh_flags   = flags;
    shdr->sh_addr    = 0;
    shdr->sh_link    = link;
    shdr->sh_info    = info;
    shdr->sh_entsize = entsize;
  } else {
    Elf32_Shdr *shdr = elf32_getshdr(scn);
    shdr->sh_name    = name_off;
    shdr->sh_type    = type;
    shdr->sh_flags   = flags;
    shdr->sh_addr    = 0;
    shdr->sh_link    = link;
    shdr->sh_info    = info;
    shdr->sh_entsize = entsize;
  }
}

static void initscn(Elf_Scn *scn, const char *name, int type, int flags,
             int link, int info, int size) {
  size_t name_off = name ? newstr(name) : 0;
  sh_set(scn, name_off, type, flags, link, info, size);
}

static void scnname(Elf_Scn *scn, const char *name) {
  size_t name_off = newstr(name);
  if (is64) {
    elf64_getshdr(scn)->sh_name = name_off;
  } else {
    elf32_getshdr(scn)->sh_name = name_off;
  }
}

/*
 * Relocation table - one per data section, stored in a scntbl.
 * newreloc() appends a relocation entry to the section's buffer.
 * i386 uses Elf32_Rel (REL); AMD64 uses Elf64_Rela (RELA).
 */
typedef struct scntbl {
  Elf_Scn  *scn;
  Elf_Data *data;
  void     *relbuf;
  int       relcount;
  int       relalloc;
} scntbl;

static FILE* in; /* input text in TOF */
static char* cmdname;
#define LINESIZE 1024

static scntbl *relocscn(Elf *elf, int index) {
  scntbl *ret = calloc(1, sizeof(scntbl));
  if (!ret) { perror("calloc"); exit(1); }
  ret->scn = elf_newscn(elf);
  if (is64) {
    initscn(ret->scn, NULL, SHT_RELA, 0, elf_ndxscn(symscn),
            index, sizeof(Elf64_Rela));
  } else {
    initscn(ret->scn, NULL, SHT_REL, 0, elf_ndxscn(symscn),
            index, sizeof(Elf32_Rel));
  }
  return ret;
}

static void newreloc(scntbl *tbl, const char *sym, int off, int add, int len, int64_t addend) {
  int idx = newsym(newstr(sym), SHN_UNDEF, 0);

  if (is64) {
    Elf64_Rela rel;
    int rtype;
    rel.r_offset = off;
    if (add)
      rtype = (len == 4) ? R_X86_64_32 : R_X86_64_64;
    else
      rtype = R_X86_64_GLOB_DAT;
    rel.r_info   = ELF64_R_INFO(idx, rtype);
    rel.r_addend = addend;

    if (tbl->relcount >= tbl->relalloc) {
      tbl->relalloc = tbl->relalloc ? tbl->relalloc * 2 : 8;
      tbl->relbuf = realloc(tbl->relbuf, tbl->relalloc * sizeof(Elf64_Rela));
      if (!tbl->relbuf) { perror("realloc"); exit(1); }
    }
    ((Elf64_Rela *)tbl->relbuf)[tbl->relcount++] = rel;

    if (!tbl->data) {
      tbl->data = elf_newdata(tbl->scn);
      tbl->data->d_type    = ELF_T_RELA;
      tbl->data->d_align   = 8;
      tbl->data->d_off     = 0;
      tbl->data->d_version = EV_CURRENT;
    }
    tbl->data->d_buf  = tbl->relbuf;
    tbl->data->d_size = tbl->relcount * sizeof(Elf64_Rela);
  } else {
    Elf32_Rel rel;
    rel.r_offset = off;
    rel.r_info   = ELF32_R_INFO(idx, add ? R_386_32 : R_386_GLOB_DAT);

    if (tbl->relcount >= tbl->relalloc) {
      tbl->relalloc = tbl->relalloc ? tbl->relalloc * 2 : 8;
      tbl->relbuf = realloc(tbl->relbuf, tbl->relalloc * sizeof(Elf32_Rel));
      if (!tbl->relbuf) { perror("realloc"); exit(1); }
    }
    ((Elf32_Rel *)tbl->relbuf)[tbl->relcount++] = rel;

    if (!tbl->data) {
      tbl->data = elf_newdata(tbl->scn);
      tbl->data->d_type    = ELF_T_REL;
      tbl->data->d_align   = 4;
      tbl->data->d_off     = 0;
      tbl->data->d_version = EV_CURRENT;
    }
    tbl->data->d_buf  = tbl->relbuf;
    tbl->data->d_size = tbl->relcount * sizeof(Elf32_Rel);
  }
}

void addblock(Elf *elf) {
  Elf_Data *data;
  char line[LINESIZE];
  char *name;
  Elf_Scn *scn;
  scntbl *rel;
  int i, bss, len, val, add, flags, type, align, datalen, memlen;
  char *buf;
  unsigned short shrt;
  int rellen = is64 ? 8 : 4;
  const char *relprefix = is64 ? ".rela" : ".rel";

  /* Pending reloc buffer: for AMD64 ADD relocations we need to extract the
     addend from the section data bytes, which are read after the RELOC lines.
     Buffer these entries and emit them once buf is populated. */
  struct pendrel { char *name; int val; int add; int len; };
  struct pendrel *pendrels = NULL;
  int npendrels = 0, pendrelalloc = 0;

  rel = NULL;
  scn = elf_newscn(elf);
  while (1) {
    if (fgets(line, sizeof line, in) == 0) {
      UNEXPECTED_EOF;
    }
    if (line[0] != 'S' || line[1] != 'Y' || line[2] != 'M')
      break;
    name = malloc(strlen(line) * sizeof(char));
    sscanf(line+5, "%s %d", name, &val);
    newsym(newstr(name), elf_ndxscn(scn), val);
  }
  while (1) {
    if (line[0] != 'R' || line[1] != 'E' || line[2] != 'L')
      break;
    add = (line[7] == 'A');
    if (!add && line[7] != 'S')
      BUG(4);
    name = malloc(strlen(line) * sizeof(char));
    sscanf(line+11, "%d %d %s", &val, &len, name);
    if (len != 4 && len != 8)
      BUG(3);
    if (is64) {
      /* AMD64: accept both 4-byte (R_X86_64_32) and 8-byte (R_X86_64_64) relocs */
    } else {
      if (len != rellen)
        BUG(3);
    }
    if (!rel)
      rel = relocscn(elf, elf_ndxscn(scn));
    if (is64 && add) {
      /* Buffer ADD relocs for amd64: addend lives in the section bytes,
         which we haven't read yet. Emit after buf is populated. */
      if (npendrels >= pendrelalloc) {
        pendrelalloc = pendrelalloc ? pendrelalloc * 2 : 4;
        pendrels = realloc(pendrels, pendrelalloc * sizeof(*pendrels));
        if (!pendrels) { perror("realloc"); exit(1); }
      }
      pendrels[npendrels].name = name;
      pendrels[npendrels].val  = val;
      pendrels[npendrels].add  = add;
      pendrels[npendrels].len  = len;
      npendrels++;
    } else {
      newreloc(rel, name, val, add, len, 0);
    }
    if (fgets(line, sizeof line, in) == 0) {
      UNEXPECTED_EOF;
    }
  }
  flags = 0;
  if (line[1] == 'w')
    flags |= SHF_WRITE;
  if (line[2] == 'x')
    flags |= SHF_EXECINSTR;
  sscanf(line+6, " %d %d %d", &datalen, &memlen, &align);
  type = SHT_PROGBITS;
  if (!datalen)
    type = SHT_NOBITS;
  if (!datalen && !memlen)
    type = SHT_NULL;
  if (memlen != 0)
    flags |= SHF_ALLOC;
  bss = 0;
  if (datalen > 0 && line[2] == 'x') {
    if (line[1] == 'w') {
      name = ".init";
      flags = SHF_ALLOC|SHF_EXECINSTR|SHF_WRITE;
      type = SHT_PROGBITS;
    } else {
      name = ".text";
      flags = SHF_ALLOC|SHF_EXECINSTR;
      type = SHT_PROGBITS;
    }
  } else if (!datalen && memlen && line[1] == 'w') {
    name = ".bss";
    flags = SHF_ALLOC|SHF_WRITE;
    bss = 1;
  } else if (datalen && line[1] != 'w') {
    name = ".rodata";
    flags = SHF_ALLOC;
  } else {
    name = ".private";
  }
  initscn(scn, name, type, flags, SHN_UNDEF, 0, memlen);
  if (rel) {
    buf = malloc(1 + strlen(relprefix) + strlen(name));
    strcpy(buf, relprefix);
    strcat(buf, name);
    scnname(rel->scn, buf);
    free(buf);
  }
  if (fgets(line, sizeof line, in) == 0) {
    UNEXPECTED_EOF;
  }
  if (strcmp(line, "{\n") != 0)
    BUG(7);
  if (!bss) {
    buf = malloc(datalen > memlen ? datalen : memlen);
    for (i = 0; i < datalen; ++i) {
      if (fscanf(in, "%hu ", &shrt) != 1)
        UNEXPECTED_EOF;
      buf[i] = shrt;
    }
    for (; i < memlen; ++i)
      buf[i] = 0;
    /* Emit buffered AMD64 ADD relocations now that buf is available.
       Extract the little-endian addend from the section bytes at reloc offset. */
    if (npendrels > 0) {
      int k;
      for (k = 0; k < npendrels; k++) {
        int64_t addend = 0;
        int roff = pendrels[k].val;
        int rlen = pendrels[k].len;
        if (roff >= 0 && roff + rlen <= datalen) {
          int m;
          for (m = rlen - 1; m >= 0; m--)
            addend = (addend << 8) | ((unsigned char)buf[roff + m]);
        }
        newreloc(rel, pendrels[k].name, pendrels[k].val,
                 pendrels[k].add, pendrels[k].len, addend);
      }
      free(pendrels);
    }
    data = elf_newdata(scn);
    data->d_buf     = buf;
    data->d_type    = ELF_T_BYTE;
    data->d_off     = 0;
    data->d_size    = i;
    data->d_align   = align;
    data->d_version = EV_CURRENT;
  } else {
    free(pendrels);
    data = elf_newdata(scn);
    data->d_buf     = NULL;
    data->d_type    = ELF_T_BYTE;
    data->d_off     = 0;
    data->d_size    = memlen;
    data->d_align   = align;
    data->d_version = EV_CURRENT;
  }
  if (fgets(line, sizeof line, in) == 0) {
    UNEXPECTED_EOF;
  }
  if (strcmp(line, "}\n") != 0) {
    BUG(10);
  }
}


int main(int argc, char **argv) {
  int fd;
  Elf *elf;
  Elf_Scn *scn;
  char line[LINESIZE];
  char *usage = "Usage: %s [-o outfile] [-arch i386|amd64] [infile]\n";
  char *outfile = 0;
  int opt;

  cmdname = *argv;

  /* Parse options manually (getopt doesn't handle multi-char flags) */
  int i;
  for (i = 1; i < argc; ) {
    if (strcmp(argv[i], "-o") == 0) {
      if (i+1 >= argc) { fprintf(stderr, usage, cmdname); return 1; }
      outfile = argv[i+1];
      i += 2;
    } else if (strcmp(argv[i], "-arch") == 0) {
      if (i+1 >= argc) { fprintf(stderr, usage, cmdname); return 1; }
      if (strcmp(argv[i+1], "amd64") == 0 ||
          strcmp(argv[i+1], "AMD64") == 0 ||
          strcmp(argv[i+1], "x86_64") == 0) {
        is64 = 1;
      } else if (strcmp(argv[i+1], "i386") == 0 ||
                 strcmp(argv[i+1], "I386") == 0 ||
                 strcmp(argv[i+1], "x86") == 0) {
        is64 = 0;
      } else {
        fprintf(stderr, "%s: unknown arch: %s\n", cmdname, argv[i+1]);
        fprintf(stderr, usage, cmdname);
        return 1;
      }
      i += 2;
    } else if (argv[i][0] == '-') {
      fprintf(stderr, usage, cmdname); return 1;
    } else {
      break;
    }
  }
  /* Remaining args: optional input file */
  if (i >= argc) {
    in = stdin;
  } else if (i == argc-1) {
    if ((in = fopen(argv[i], "r")) == 0) {
      perror(argv[i]);
      return 1;
    }
  } else {
    fprintf(stderr, usage, cmdname); return 1;
  }

  if (outfile) {
    fd = open(outfile, O_RDWR|O_CREAT|O_TRUNC, 0666);
    if (fd < 0) {
      perror(outfile);
      return 1;
    }
  } else {
    fd = 1; /* stdout */
  }

  elf_version(EV_CURRENT);
  elf = elf_begin(fd, ELF_C_WRITE, NULL);

  if (is64) {
    Elf64_Ehdr *ehdr = elf64_newehdr(elf);
    ehdr->e_machine = EM_X86_64;
    ehdr->e_version = EV_CURRENT;
    ehdr->e_entry   = 0;
  } else {
    Elf32_Ehdr *ehdr = elf32_newehdr(elf);
    ehdr->e_machine = EM_386;
    ehdr->e_version = EV_CURRENT;
    ehdr->e_entry   = 0;
  }

  /* String table section - must be first so e_shstrndx is set before
     any initscn() calls that need to add names. */
  strscn = elf_newscn(elf);
  if (is64)
    elf64_getshdr(strscn); /* touch to allocate */
  else
    elf32_getshdr(strscn);

  /* We need the strscn index before we can set e_shstrndx on ehdr.
     For ELF64 we access ehdr again after creation. */
  if (is64) {
    Elf64_Ehdr *ehdr = elf64_getehdr(elf);
    ehdr->e_shstrndx = elf_ndxscn(strscn);
  } else {
    Elf32_Ehdr *ehdr = elf32_getehdr(elf);
    ehdr->e_shstrndx = elf_ndxscn(strscn);
  }

  newstr("");                               /* mandatory empty string at 0 */
  initscn(strscn, ".strtab", SHT_STRTAB, 0, SHN_UNDEF, 0, 0);

  /* Symbol table section */
  scn = elf_newscn(elf);
  symscn = scn;
  {
    int esz = is64 ? sizeof(Elf64_Sym) : sizeof(Elf32_Sym);
    initscn(scn, ".symtab", SHT_SYMTAB, 0, elf_ndxscn(strscn), 0, esz);
  }
  newsym(0, 0, 0);   /* mandatory null symbol at index 0 */

  /* Data sections (one per "NEW BLOCK" in the TOF input) */
  for (;;) {
    if (fgets(line, sizeof line, in) == 0) {
      UNEXPECTED_EOF;
    }
    if (strcmp(line, "END\n") == 0)
      break;
    if (strcmp(line, "NEW BLOCK\n") != 0) {
      BUG(2);
    }
    addblock(elf);
  }

  elf_update(elf, ELF_C_WRITE);
  elf_end(elf);
  return 0;
}
