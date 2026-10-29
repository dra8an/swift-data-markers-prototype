// Prints the ICU converter that each encoding name resolves to, with the system ICU of macOS.
// Build: clang -w cnv.c -licucore -o cnv
// Run:   ./cnv EUC-JP ISO-8859-1 Shift_JIS ISO-8859-2 windows-1251 windows-1252 windows-1253 windows-1254 windows-1250 ISO-2022-JP macintosh
// These are the 11 names in swift-foundation's ICU+StringConverter.swift (main bfbded0f70).
#include <stdio.h>
typedef struct UConverter UConverter; typedef int UErrorCode;
UConverter* ucnv_open(const char*, UErrorCode*); const char* ucnv_getName(const UConverter*, UErrorCode*); void ucnv_close(UConverter*);
int main(int c, char**v){ for(int i=1;i<c;i++){ UErrorCode s=0; UConverter*u=ucnv_open(v[i],&s); if(s>0){printf("%s -> error %d\n",v[i],s);continue;} printf("%s -> %s\n",v[i],ucnv_getName(u,&s)); ucnv_close(u);} return 0; }
