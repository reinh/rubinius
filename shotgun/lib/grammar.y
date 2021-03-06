/**********************************************************************

  parse.y -

  $Author: matz $
  $Date: 2004/11/29 06:13:51 $
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

%{

#define YYDEBUG 1
#define YYERROR_VERBOSE 1

#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <stdbool.h>

#include "shotgun/lib/grammar_internal.h"
#include "shotgun/lib/grammar_runtime.h"
#include "shotgun/lib/array.h"

static NODE *syd_node_newnode(rb_parse_state*, enum node_type, OBJECT, OBJECT, OBJECT);

#undef VALUE

#ifndef isnumber
#define isnumber isdigit
#endif

#define ISALPHA isalpha
#define ISSPACE isspace
#define ISALNUM(x) (isalpha(x) || isnumber(x))
#define ISDIGIT isdigit
#define ISXDIGIT isxdigit
#define ISUPPER isupper

#define ismbchar(c) (0)
#define mbclen(c) (1)

#define ID2SYM(i) (OBJECT)i

#define string_new(ptr, len) blk2bstr(ptr, len)
#define string_new2(ptr) cstr2bstr(ptr)

intptr_t syd_sourceline;
static char *syd_sourcefile;

#define ruby_sourceline syd_sourceline
#define ruby_sourcefile syd_sourcefile

static int
syd_yyerror(const char *, rb_parse_state*);
#define yyparse syd_yyparse
#define yylex syd_yylex
#define yyerror(str) syd_yyerror(str, parse_state)
#define yylval syd_yylval
#define yychar syd_yychar
#define yydebug syd_yydebug

#define YYPARSE_PARAM parse_state
#define YYLEX_PARAM parse_state

#define ID_SCOPE_SHIFT 3
#define ID_SCOPE_MASK 0x07
#define ID_LOCAL    0x01
#define ID_INSTANCE 0x02
#define ID_GLOBAL   0x03
#define ID_ATTRSET  0x04
#define ID_CONST    0x05
#define ID_CLASS    0x06
#define ID_JUNK     0x07
#define ID_INTERNAL ID_JUNK

#define is_notop_id(id) ((id)>tLAST_TOKEN)
#define is_local_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_LOCAL)
#define is_global_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_GLOBAL)
#define is_instance_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_INSTANCE)
#define is_attrset_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_ATTRSET)
#define is_const_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_CONST)
#define is_class_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_CLASS)
#define is_junk_id(id) (is_notop_id(id)&&((id)&ID_SCOPE_MASK)==ID_JUNK)

#define is_asgn_or_id(id) ((is_notop_id(id)) && \
        (((id)&ID_SCOPE_MASK) == ID_GLOBAL || \
         ((id)&ID_SCOPE_MASK) == ID_INSTANCE || \
         ((id)&ID_SCOPE_MASK) == ID_CLASS))


/* FIXME these went into the ruby_state instead of parse_state
   because a ton of other crap depends on it 
char *ruby_sourcefile;          current source file
int   ruby_sourceline;          current line no.
*/
static int yylex();


#define BITSTACK_PUSH(stack, n) (stack = (stack<<1)|((n)&1))
#define BITSTACK_POP(stack)     (stack >>= 1)
#define BITSTACK_LEXPOP(stack)  (stack = (stack >> 1) | (stack & 1))
#define BITSTACK_SET_P(stack)   (stack&1)

#define COND_PUSH(n)    BITSTACK_PUSH(vps->cond_stack, n)
#define COND_POP()      BITSTACK_POP(vps->cond_stack)
#define COND_LEXPOP()   BITSTACK_LEXPOP(vps->cond_stack)
#define COND_P()        BITSTACK_SET_P(vps->cond_stack)

#define CMDARG_PUSH(n)  BITSTACK_PUSH(vps->cmdarg_stack, n)
#define CMDARG_POP()    BITSTACK_POP(vps->cmdarg_stack)
#define CMDARG_LEXPOP() BITSTACK_LEXPOP(vps->cmdarg_stack)
#define CMDARG_P()      BITSTACK_SET_P(vps->cmdarg_stack)

/*
static int class_nest = 0;
static int in_single = 0;
static int in_def = 0;
static int compile_for_eval = 0;
static ID cur_mid = 0;
*/

static NODE *cond(NODE*,rb_parse_state*);
static NODE *logop(enum node_type,NODE*,NODE*,rb_parse_state*);
static int cond_negative(NODE**);

static NODE *newline_node(rb_parse_state*,NODE*);
static void fixpos(NODE*,NODE*);

static int value_expr0(NODE*,rb_parse_state*);
static void void_expr0(NODE *);
static void void_stmts(NODE*,rb_parse_state*);
static NODE *remove_begin(NODE*);
#define  value_expr(node)  value_expr0((node) = remove_begin(node), parse_state)
#define void_expr(node) void_expr0((node) = remove_begin(node))

static NODE *block_append(rb_parse_state*,NODE*,NODE*);
static NODE *list_append(rb_parse_state*,NODE*,NODE*);
static NODE *list_concat(NODE*,NODE*);
static NODE *arg_concat(rb_parse_state*,NODE*,NODE*);
static NODE *arg_prepend(rb_parse_state*,NODE*,NODE*);
static NODE *literal_concat(rb_parse_state*,NODE*,NODE*);
static NODE *new_evstr(rb_parse_state*,NODE*);
static NODE *evstr2dstr(rb_parse_state*,NODE*);
static NODE *call_op(NODE*,ID,int,NODE*,rb_parse_state*);

/* static NODE *negate_lit(NODE*); */
static NODE *ret_args(rb_parse_state*,NODE*);
static NODE *arg_blk_pass(NODE*,NODE*);
static NODE *new_call(rb_parse_state*,NODE*,ID,NODE*);
static NODE *new_fcall(rb_parse_state*,ID,NODE*);
static NODE *new_super(rb_parse_state*,NODE*);
static NODE *new_yield(rb_parse_state*,NODE*);

static NODE *syd_gettable(rb_parse_state*,ID);
#define gettable(i) syd_gettable(parse_state, i)
static NODE *assignable(ID,NODE*,rb_parse_state*);
static NODE *aryset(NODE*,NODE*,rb_parse_state*);
static NODE *attrset(NODE*,ID,rb_parse_state*);
static void rb_backref_error(NODE*);
static NODE *node_assign(NODE*,NODE*,rb_parse_state*);

static NODE *match_gen(NODE*,NODE*,rb_parse_state*);
static void syd_local_push(rb_parse_state*, int cnt);
#define local_push(cnt) syd_local_push(vps, cnt)
static void syd_local_pop(rb_parse_state*);
#define local_pop() syd_local_pop(vps)
static intptr_t  syd_local_cnt(rb_parse_state*,ID);
#define local_cnt(i) syd_local_cnt(vps, i)
static int  syd_local_id(rb_parse_state*,ID);
#define local_id(i) syd_local_id(vps, i)
static ID  *syd_local_tbl();
static ID   convert_op();

static void tokadd(char c, rb_parse_state *parse_state);
static int tokadd_string(int, int, int, int *, rb_parse_state*);
 
#define SHOW_PARSER_WARNS 0
 
static int _debug_print(const char *fmt, ...) {
#if SHOW_PARSER_WARNS
  va_list ar;
  int i;

  va_start(ar, fmt);
  i = vprintf(fmt, ar);
  va_end(ar);
  return i;
#else
  return 0;
#endif
}
 
#define rb_warn _debug_print
#define rb_warning _debug_print
#define rb_compile_error _debug_print

static ID rb_intern(const char *name);
static ID rb_id_attrset(ID);

rb_parse_state *alloc_parse_state();
static unsigned long scan_oct(const char *start, int len, int *retlen);
static unsigned long scan_hex(const char *start, int len, int *retlen);

static void reset_block(rb_parse_state *parse_state);
static NODE *extract_block_vars(rb_parse_state *parse_state, NODE* node, var_table vars);

#define ruby_verbose 0
#define RE_OPTION_ONCE 0x80
#define RE_OPTION_IGNORECASE (1L)
#define RE_OPTION_EXTENDED   (RE_OPTION_IGNORECASE<<1)
#define RE_OPTION_MULTILINE  (RE_OPTION_EXTENDED<<1)
#define RE_OPTION_SINGLELINE (RE_OPTION_MULTILINE<<1)
#define RE_OPTION_LONGEST    (RE_OPTION_SINGLELINE<<1)
#define RE_MAY_IGNORECASE    (RE_OPTION_LONGEST<<1)
#define RE_OPTIMIZE_ANCHOR   (RE_MAY_IGNORECASE<<1)
#define RE_OPTIMIZE_EXACTN   (RE_OPTIMIZE_ANCHOR<<1)
#define RE_OPTIMIZE_NO_BM    (RE_OPTIMIZE_EXACTN<<1)
#define RE_OPTIMIZE_BMATCH   (RE_OPTIMIZE_NO_BM<<1)

#define NODE_STRTERM NODE_ZARRAY        /* nothing to gc */
#define NODE_HEREDOC NODE_ARRAY         /* 1, 3 to gc */
#define SIGN_EXTEND(x,n) (((1<<((n)-1))^((x)&~(~0<<(n))))-(1<<((n)-1)))
#define nd_func u1.id
#if SIZEOF_SHORT != 2
#define nd_term(node) SIGN_EXTEND((node)->u2.id, (CHAR_BIT*2))
#else
#define nd_term(node) ((signed short)(node)->u2.id)
#endif
#define nd_paren(node) (char)((node)->u2.id >> (CHAR_BIT*2))
#define nd_nest u3.id

/* Older versions of Yacc set YYMAXDEPTH to a very low value by default (150,
   for instance).  This is too low for Ruby to parse some files, such as
   date/format.rb, therefore bump the value up to at least Bison's default. */
#ifdef OLD_YACC
#ifndef YYMAXDEPTH
#define YYMAXDEPTH 10000
#endif
#endif

#define vps ((rb_parse_state*)parse_state)

%}

%pure-parser

%union {
    NODE *node;
    ID id;
    int num;
    var_table vars;
}

%token  kCLASS
        kMODULE
        kDEF
        kUNDEF
        kBEGIN
        kRESCUE
        kENSURE
        kEND
        kIF
        kUNLESS
        kTHEN
        kELSIF
        kELSE
        kCASE
        kWHEN
        kWHILE
        kUNTIL
        kFOR
        kBREAK
        kNEXT
        kREDO
        kRETRY
        kIN
        kDO
        kDO_COND
        kDO_BLOCK
        kRETURN
        kYIELD
        kSUPER
        kSELF
        kNIL
        kTRUE
        kFALSE
        kAND
        kOR
        kNOT
        kIF_MOD
        kUNLESS_MOD
        kWHILE_MOD
        kUNTIL_MOD
        kRESCUE_MOD
        kALIAS
        kDEFINED
        klBEGIN
        klEND
        k__LINE__
        k__FILE__

%token <id>   tIDENTIFIER tFID tGVAR tIVAR tCONSTANT tCVAR tXSTRING_BEG
%token <node> tINTEGER tFLOAT tSTRING_CONTENT
%token <node> tNTH_REF tBACK_REF
%token <num>  tREGEXP_END 
%type <node> singleton strings string string1 xstring regexp
%type <node> string_contents xstring_contents string_content
%type <node> words qwords word_list qword_list word
%type <node> literal numeric dsym cpath
%type <node> bodystmt compstmt stmts stmt expr arg primary command command_call method_call
%type <node> expr_value arg_value primary_value
%type <node> if_tail opt_else case_body cases opt_rescue exc_list exc_var opt_ensure
%type <node> args when_args call_args call_args2 open_args paren_args opt_paren_args
%type <node> command_args aref_args opt_block_arg block_arg var_ref var_lhs
%type <node> mrhs superclass block_call block_command
%type <node> f_arglist f_args f_optarg f_opt f_block_arg opt_f_block_arg
%type <node> assoc_list assocs assoc undef_list backref string_dvar
%type <node> block_var opt_block_var brace_block cmd_brace_block do_block lhs none
%type <node> mlhs mlhs_head mlhs_basic mlhs_entry mlhs_item mlhs_node
%type <id>   fitem variable sym symbol operation operation2 operation3
%type <id>   cname fname op f_rest_arg
%type <num>  f_norm_arg f_arg
%token tUPLUS           /* unary+ */
%token tUMINUS          /* unary- */
%token tUBS             /* unary\ */
%token tPOW             /* ** */
%token tCMP             /* <=> */
%token tEQ              /* == */
%token tEQQ             /* === */
%token tNEQ             /* != */
%token tGEQ             /* >= */
%token tLEQ             /* <= */
%token tANDOP tOROP     /* && and || */
%token tMATCH tNMATCH   /* =~ and !~ */
%token tDOT2 tDOT3      /* .. and ... */
%token tAREF tASET      /* [] and []= */
%token tLSHFT tRSHFT    /* << and >> */
%token tCOLON2          /* :: */
%token tCOLON3          /* :: at EXPR_BEG */
%token <id> tOP_ASGN    /* +=, -=  etc. */
%token tASSOC           /* => */
%token tLPAREN          /* ( */
%token tLPAREN_ARG      /* ( */
%token tRPAREN          /* ) */
%token tLBRACK          /* [ */
%token tLBRACE          /* { */
%token tLBRACE_ARG      /* { */
%token tSTAR            /* * */
%token tAMPER           /* & */
%token tSYMBEG tSTRING_BEG tREGEXP_BEG tWORDS_BEG tQWORDS_BEG
%token tSTRING_DBEG tSTRING_DVAR tSTRING_END

/*
 *      precedence table
 */

%nonassoc tLOWEST
%nonassoc tLBRACE_ARG

%nonassoc  kIF_MOD kUNLESS_MOD kWHILE_MOD kUNTIL_MOD
%left  kOR kAND
%right kNOT
%nonassoc kDEFINED
%right '=' tOP_ASGN
%left kRESCUE_MOD
%right '?' ':'
%nonassoc tDOT2 tDOT3
%left  tOROP
%left  tANDOP
%nonassoc  tCMP tEQ tEQQ tNEQ tMATCH tNMATCH
%left  '>' tGEQ '<' tLEQ
%left  '|' '^'
%left  '&'
%left  tLSHFT tRSHFT
%left  '+' '-'
%left  '*' '/' '%'
%right tUMINUS_NUM tUMINUS
%right tPOW
%right '!' '~' tUPLUS

%token tLAST_TOKEN

%%
program         :  {
                        vps->lex_state = EXPR_BEG;
                        vps->variables = var_table_create();
                        class_nest = 0;
                    }
                  compstmt
                    {
                        if ($2 && !compile_for_eval) {
                            /* last expression should not be void */
                            if (nd_type($2) != NODE_BLOCK) void_expr($2);
                            else {
                                NODE *node = $2;
                                while (node->nd_next) {
                                    node = node->nd_next;
                                }
                                void_expr(node->nd_head);
                            }
                        }
                        vps->top = block_append(parse_state, vps->top, $2); 
                        class_nest = 0;
                    }
                ;

bodystmt        : compstmt
                  opt_rescue
                  opt_else
                  opt_ensure
                    {
                        $$ = $1;
                        if ($2) {
                            $$ = NEW_RESCUE($1, $2, $3);
                        }
                        else if ($3) {
                            rb_warn("else without rescue is useless");
                            $$ = block_append(parse_state, $$, $3);
                        }
                        if ($4) {
                            $$ = NEW_ENSURE($$, $4);
                        }
                        fixpos($$, $1);
                    }
                ;

compstmt        : stmts opt_terms
                    {
                        void_stmts($1, parse_state);
                        $$ = $1;
                    }
                ;

stmts           : none
                | stmt
                    {
                        $$ = newline_node(parse_state, $1);
                    }
                | stmts terms stmt
                    {
                        $$ = block_append(parse_state, $1, newline_node(parse_state, $3));
                    }
                | error stmt
                    {
                        $$ = $2;
                    }
                ;

stmt            : kALIAS fitem {vps->lex_state = EXPR_FNAME;} fitem
                    {
                        $$ = NEW_ALIAS($2, $4);
                    }
                | kALIAS tGVAR tGVAR
                    {
                        $$ = NEW_VALIAS($2, $3);
                    }
                | kALIAS tGVAR tBACK_REF
                    {
                        char buf[3];

                        snprintf(buf, sizeof(buf), "$%c", (char)$3->nd_nth);
                        $$ = NEW_VALIAS($2, rb_intern(buf));
                    }
                | kALIAS tGVAR tNTH_REF
                    {
                        yyerror("can't make alias for the number variables");
                        $$ = 0;
                    }
                | kUNDEF undef_list
                    {
                        $$ = $2;
                    }
                | stmt kIF_MOD expr_value
                    {
                        $$ = NEW_IF(cond($3, parse_state), $1, 0);
                        fixpos($$, $3);
                        if (cond_negative(&$$->nd_cond)) {
                            $$->nd_else = $$->nd_body;
                            $$->nd_body = 0;
                        }
                    }
                | stmt kUNLESS_MOD expr_value
                    {
                        $$ = NEW_UNLESS(cond($3, parse_state), $1, 0);
                        fixpos($$, $3);
                        if (cond_negative(&$$->nd_cond)) {
                            $$->nd_body = $$->nd_else;
                            $$->nd_else = 0;
                        }
                    }
                | stmt kWHILE_MOD expr_value
                    {
                        if ($1 && nd_type($1) == NODE_BEGIN) {
                            $$ = NEW_WHILE(cond($3, parse_state), $1->nd_body, 0);
                        }
                        else {
                            $$ = NEW_WHILE(cond($3, parse_state), $1, 1);
                        }
                        if (cond_negative(&$$->nd_cond)) {
                            nd_set_type($$, NODE_UNTIL);
                        }
                    }
                | stmt kUNTIL_MOD expr_value
                    {
                        if ($1 && nd_type($1) == NODE_BEGIN) {
                            $$ = NEW_UNTIL(cond($3, parse_state), $1->nd_body, 0);
                        }
                        else {
                            $$ = NEW_UNTIL(cond($3, parse_state), $1, 1);
                        }
                        if (cond_negative(&$$->nd_cond)) {
                            nd_set_type($$, NODE_WHILE);
                        }
                    }
                | stmt kRESCUE_MOD stmt
                    {
                        $$ = NEW_RESCUE($1, NEW_RESBODY(0,$3,0), 0);
                    }
                | klBEGIN
                    {
                        if (in_def || in_single) {
                            yyerror("BEGIN in method");
                        }
                        local_push(0);
                    }
                  '{' compstmt '}'
                    {
                        /*
                        ruby_eval_tree_begin = block_append(ruby_eval_tree_begin,
                                                            NEW_PREEXE($4));
                        */
                        local_pop();
                        $$ = 0;
                    }
                | klEND '{' compstmt '}'
                    {
                        if (in_def || in_single) {
                            rb_warn("END in method; use at_exit");
                        }

                        $$ = NEW_ITER(0, NEW_POSTEXE(), $3);
                    }
                | lhs '=' command_call
                    {
                        $$ = node_assign($1, $3, parse_state);
                    }
                | mlhs '=' command_call
                    {
                        value_expr($3);
                        $1->nd_value = ($1->nd_head) ? NEW_TO_ARY($3) : NEW_ARRAY($3);
                        $$ = $1;
                    }
                | var_lhs tOP_ASGN command_call
                    {
                        value_expr($3);
                        if ($1) {
                            ID vid = $1->nd_vid;
                            if ($2 == tOROP) {
                                $1->nd_value = $3;
                                $$ = NEW_OP_ASGN_OR(gettable(vid), $1);
                                if (is_asgn_or_id(vid)) {
                                    $$->nd_aid = vid;
                                }
                            }
                            else if ($2 == tANDOP) {
                                $1->nd_value = $3;
                                $$ = NEW_OP_ASGN_AND(gettable(vid), $1);
                            }
                            else {
                                $$ = $1;
                                $$->nd_value = call_op(gettable(vid),$2,1,$3, parse_state);
                            }
                        }
                        else {
                            $$ = 0;
                        }
                    }
                | primary_value '[' aref_args ']' tOP_ASGN command_call
                    {
                        NODE *args;

                        value_expr($6);
                        args = NEW_LIST($6);
                        if ($3 && nd_type($3) != NODE_ARRAY)
                            $3 = NEW_LIST($3);
                        $3 = list_append(parse_state, $3, NEW_NIL());
                        list_concat(args, $3);
                        if ($5 == tOROP) {
                            $5 = 0;
                        }
                        else if ($5 == tANDOP) {
                            $5 = 1;
                        }
                        $$ = NEW_OP_ASGN1($1, $5, args);
                        fixpos($$, $1);
                    }
                | primary_value '.' tIDENTIFIER tOP_ASGN command_call
                    {
                        value_expr($5);
                        if ($4 == tOROP) {
                            $4 = 0;
                        }
                        else if ($4 == tANDOP) {
                            $4 = 1;
                        }
                        $$ = NEW_OP_ASGN2($1, $3, $4, $5);
                        fixpos($$, $1);
                    }
                | primary_value '.' tCONSTANT tOP_ASGN command_call
                    {
                        value_expr($5);
                        if ($4 == tOROP) {
                            $4 = 0;
                        }
                        else if ($4 == tANDOP) {
                            $4 = 1;
                        }
                        $$ = NEW_OP_ASGN2($1, $3, $4, $5);
                        fixpos($$, $1);
                    }
                | primary_value tCOLON2 tIDENTIFIER tOP_ASGN command_call
                    {
                        value_expr($5);
                        if ($4 == tOROP) {
                            $4 = 0;
                        }
                        else if ($4 == tANDOP) {
                            $4 = 1;
                        }
                        $$ = NEW_OP_ASGN2($1, $3, $4, $5);
                        fixpos($$, $1);
                    }
                | backref tOP_ASGN command_call
                    {
                        rb_backref_error($1);
                        $$ = 0;
                    }
                | lhs '=' mrhs
                    {
                        $$ = node_assign($1, NEW_SVALUE($3), parse_state);
                    }
                | mlhs '=' arg_value
                    {
                        $1->nd_value = ($1->nd_head) ? NEW_TO_ARY($3) : NEW_ARRAY($3);
                        $$ = $1;
                    }
                | mlhs '=' mrhs
                    {
                        $1->nd_value = $3;
                        $$ = $1;
                    }
                | expr
                ;

expr            : command_call
                | expr kAND expr
                    {
                        $$ = logop(NODE_AND, $1, $3, parse_state);
                    }
                | expr kOR expr
                    {
                        $$ = logop(NODE_OR, $1, $3, parse_state);
                    }
                | kNOT expr
                    {
                        $$ = NEW_NOT(cond($2, parse_state));
                    }
                | '!' command_call
                    {
                        $$ = NEW_NOT(cond($2, parse_state));
                    }
                | arg
                ;

expr_value      : expr
                    {
                        value_expr($$);
                        $$ = $1;
                    }
                ;

command_call    : command
                | block_command
                | kRETURN call_args
                    {
                        $$ = NEW_RETURN(ret_args(vps, $2));
                    }
                | kBREAK call_args
                    {
                        $$ = NEW_BREAK(ret_args(vps, $2));
                    }
                | kNEXT call_args
                    {
                        $$ = NEW_NEXT(ret_args(vps, $2));
                    }
                ;

block_command   : block_call
                | block_call '.' operation2 command_args
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                    }
                | block_call tCOLON2 operation2 command_args
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                    }
                ;

cmd_brace_block : tLBRACE_ARG
                    {
                        $<num>1 = ruby_sourceline;
                        reset_block(vps);
                    }
                  opt_block_var { $<vars>$ = vps->block_vars; }
                  compstmt
                  '}'
                    {
                        $$ = NEW_ITER($3, 0, extract_block_vars(vps, $5, $<vars>4));
                        nd_set_line($$, $<num>1);
                    }
                ;

command         : operation command_args       %prec tLOWEST
                    {
                        $$ = new_fcall(parse_state, $1, $2);
                        fixpos($$, $2);
                   }
                | operation command_args cmd_brace_block
                    {
                        $$ = new_fcall(parse_state, $1, $2);
                        if ($3) {
                            if (nd_type($$) == NODE_BLOCK_PASS) {
                                rb_compile_error("both block arg and actual block given");
                            }
                            $3->nd_iter = $$;
                            $$ = $3;
                        }
                        fixpos($$, $2);
                   }
                | primary_value '.' operation2 command_args     %prec tLOWEST
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                        fixpos($$, $1);
                    }
                | primary_value '.' operation2 command_args cmd_brace_block
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                        if ($5) {
                            if (nd_type($$) == NODE_BLOCK_PASS) {
                                rb_compile_error("both block arg and actual block given");
                            }
                            $5->nd_iter = $$;
                            $$ = $5;
                        }
                        fixpos($$, $1);
                   }
                | primary_value tCOLON2 operation2 command_args %prec tLOWEST
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                        fixpos($$, $1);
                    }
                | primary_value tCOLON2 operation2 command_args cmd_brace_block
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                        if ($5) {
                            if (nd_type($$) == NODE_BLOCK_PASS) {
                                rb_compile_error("both block arg and actual block given");
                            }
                            $5->nd_iter = $$;
                            $$ = $5;
                        }
                        fixpos($$, $1);
                   }
                | kSUPER command_args
                    {
                        $$ = new_super(parse_state, $2);
                        fixpos($$, $2);
                    }
                | kYIELD command_args
                    {
                        $$ = new_yield(parse_state, $2);
                        fixpos($$, $2);
                    }
                ;

mlhs            : mlhs_basic
                | tLPAREN mlhs_entry ')'
                    {
                        $$ = $2;
                    }
                ;

mlhs_entry      : mlhs_basic
                | tLPAREN mlhs_entry ')'
                    {
                        $$ = NEW_MASGN(NEW_LIST($2), 0);
                    }
                ;

mlhs_basic      : mlhs_head
                    {
                        $$ = NEW_MASGN($1, 0);
                    }
                | mlhs_head mlhs_item
                    {
                        $$ = NEW_MASGN(list_append(parse_state, $1,$2), 0);
                    }
                | mlhs_head tSTAR mlhs_node
                    {
                        $$ = NEW_MASGN($1, $3);
                    }
                | mlhs_head tSTAR
                    {
                        $$ = NEW_MASGN($1, -1);
                    }
                | tSTAR mlhs_node
                    {
                        $$ = NEW_MASGN(0, $2);
                    }
                | tSTAR
                    {
                        $$ = NEW_MASGN(0, -1);
                    }
                ;

mlhs_item       : mlhs_node
                | tLPAREN mlhs_entry ')'
                    {
                        $$ = $2;
                    }
                ;

mlhs_head       : mlhs_item ','
                    {
                        $$ = NEW_LIST($1);
                    }
                | mlhs_head mlhs_item ','
                    {
                        $$ = list_append(parse_state, $1, $2);
                    }
                ;

mlhs_node       : variable
                    {
                        $$ = assignable($1, 0, parse_state);
                    }
                | primary_value '[' aref_args ']'
                    {
                        $$ = aryset($1, $3, parse_state);
                    }
                | primary_value '.' tIDENTIFIER
                    {
                        $$ = attrset($1, $3, parse_state);
                    }
                | primary_value tCOLON2 tIDENTIFIER
                    {
                        $$ = attrset($1, $3, parse_state);
                    }
                | primary_value '.' tCONSTANT
                    {
                        $$ = attrset($1, $3, parse_state);
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                        if (in_def || in_single)
                            yyerror("dynamic constant assignment");
                        $$ = NEW_CDECL(0, 0, NEW_COLON2($1, $3));
                    }
                | tCOLON3 tCONSTANT
                    {
                        if (in_def || in_single)
                            yyerror("dynamic constant assignment");
                        $$ = NEW_CDECL(0, 0, NEW_COLON3($2));
                    }
                | backref
                    {
                        rb_backref_error($1);
                        $$ = 0;
                    }
                ;

lhs             : variable
                    {
                        $$ = assignable($1, 0, parse_state);
                    }
                | primary_value '[' aref_args ']'
                    {
                        $$ = aryset($1, $3, parse_state);
                    }
                | primary_value '.' tIDENTIFIER
                    {
                        $$ = attrset($1, $3, parse_state);
                    }
                | primary_value tCOLON2 tIDENTIFIER
                    {
                        $$ = attrset($1, $3, parse_state);
                    }
                | primary_value '.' tCONSTANT
                    {
                        $$ = attrset($1, $3, parse_state);
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                        if (in_def || in_single)
                            yyerror("dynamic constant assignment");
                        $$ = NEW_CDECL(0, 0, NEW_COLON2($1, $3));
                    }
                | tCOLON3 tCONSTANT
                    {
                        if (in_def || in_single)
                            yyerror("dynamic constant assignment");
                        $$ = NEW_CDECL(0, 0, NEW_COLON3($2));
                    }
                | backref
                    {
                        rb_backref_error($1);
                        $$ = 0;
                    }
                ;

cname           : tIDENTIFIER
                    {
                        yyerror("class/module name must be CONSTANT");
                    }
                | tCONSTANT
                ;

cpath           : tCOLON3 cname
                    {
                        $$ = NEW_COLON3($2);
                    }
                | cname
                    {
                        $$ = NEW_COLON2(0, $$);
                    }
                | primary_value tCOLON2 cname
                    {
                        $$ = NEW_COLON2($1, $3);
                    }
                ;

fname           : tIDENTIFIER
                | tCONSTANT
                | tFID
                | op
                    {
                        vps->lex_state = EXPR_END;
                        $$ = convert_op($1);
                    }
                | reswords
                    {
                        vps->lex_state = EXPR_END;
                        $$ = $<id>1;
                    }
                ;

fitem           : fname
                | symbol
                ;

undef_list      : fitem
                    {
                        $$ = NEW_UNDEF($1);
                    }
                | undef_list ',' {vps->lex_state = EXPR_FNAME;} fitem
                    {
                        $$ = block_append(parse_state, $1, NEW_UNDEF($4));
                    }
                ;

op              : '|'           { $$ = '|'; }
                | '^'           { $$ = '^'; }
                | '&'           { $$ = '&'; }
                | tCMP          { $$ = tCMP; }
                | tEQ           { $$ = tEQ; }
                | tEQQ          { $$ = tEQQ; }
                | tMATCH        { $$ = tMATCH; }
                | '>'           { $$ = '>'; }
                | tGEQ          { $$ = tGEQ; }
                | '<'           { $$ = '<'; }
                | tLEQ          { $$ = tLEQ; }
                | tLSHFT        { $$ = tLSHFT; }
                | tRSHFT        { $$ = tRSHFT; }
                | '+'           { $$ = '+'; }
                | '-'           { $$ = '-'; }
                | '*'           { $$ = '*'; }
                | tSTAR         { $$ = '*'; }
                | '/'           { $$ = '/'; }
                | '%'           { $$ = '%'; }
                | tPOW          { $$ = tPOW; }
                | '~'           { $$ = '~'; }
                | tUPLUS        { $$ = tUPLUS; }
                | tUMINUS       { $$ = tUMINUS; }
                | tAREF         { $$ = tAREF; }
                | tASET         { $$ = tASET; }
                | '`'           { $$ = '`'; }
                ;

reswords        : k__LINE__ | k__FILE__  | klBEGIN | klEND
                | kALIAS | kAND | kBEGIN | kBREAK | kCASE | kCLASS | kDEF
                | kDEFINED | kDO | kELSE | kELSIF | kEND | kENSURE | kFALSE
                | kFOR | kIN | kMODULE | kNEXT | kNIL | kNOT
                | kOR | kREDO | kRESCUE | kRETRY | kRETURN | kSELF | kSUPER
                | kTHEN | kTRUE | kUNDEF | kWHEN | kYIELD
                | kIF_MOD | kUNLESS_MOD | kWHILE_MOD | kUNTIL_MOD | kRESCUE_MOD
                ;

arg             : lhs '=' arg
                    {
                        $$ = node_assign($1, $3, parse_state);
                    }
                | lhs '=' arg kRESCUE_MOD arg
                    {
                        $$ = node_assign($1, NEW_RESCUE($3, NEW_RESBODY(0,$5,0), 0), parse_state);
                    }
                | var_lhs tOP_ASGN arg
                    {
                        value_expr($3);
                        if ($1) {
                            ID vid = $1->nd_vid;
                            if ($2 == tOROP) {
                                $1->nd_value = $3;
                                $$ = NEW_OP_ASGN_OR(gettable(vid), $1);
                                if (is_asgn_or_id(vid)) {
                                    $$->nd_aid = vid;
                                }
                            }
                            else if ($2 == tANDOP) {
                                $1->nd_value = $3;
                                $$ = NEW_OP_ASGN_AND(gettable(vid), $1);
                            }
                            else {
                                $$ = $1;
                                $$->nd_value = call_op(gettable(vid),$2,1,$3, parse_state);
                            }
                        }
                        else {
                            $$ = 0;
                        }
                    }
                | primary_value '[' aref_args ']' tOP_ASGN arg
                    {
                        NODE *args;

                        value_expr($6);
                        args = NEW_LIST($6);
                        if ($3 && nd_type($3) != NODE_ARRAY)
                            $3 = NEW_LIST($3);
                        $3 = list_append(parse_state, $3, NEW_NIL());
                        list_concat(args, $3);
                        if ($5 == tOROP) {
                            $5 = 0;
                        }
                        else if ($5 == tANDOP) {
                            $5 = 1;
                        }
                        $$ = NEW_OP_ASGN1($1, $5, args);
                        fixpos($$, $1);
                    }
                | primary_value '.' tIDENTIFIER tOP_ASGN arg
                    {
                        value_expr($5);
                        if ($4 == tOROP) {
                            $4 = 0;
                        }
                        else if ($4 == tANDOP) {
                            $4 = 1;
                        }
                        $$ = NEW_OP_ASGN2($1, $3, $4, $5);
                        fixpos($$, $1);
                    }
                | primary_value '.' tCONSTANT tOP_ASGN arg
                    {
                        value_expr($5);
                        if ($4 == tOROP) {
                            $4 = 0;
                        }
                        else if ($4 == tANDOP) {
                            $4 = 1;
                        }
                        $$ = NEW_OP_ASGN2($1, $3, $4, $5);
                        fixpos($$, $1);
                    }
                | primary_value tCOLON2 tIDENTIFIER tOP_ASGN arg
                    {
                        value_expr($5);
                        if ($4 == tOROP) {
                            $4 = 0;
                        }
                        else if ($4 == tANDOP) {
                            $4 = 1;
                        }
                        $$ = NEW_OP_ASGN2($1, $3, $4, $5);
                        fixpos($$, $1);
                    }
                | primary_value tCOLON2 tCONSTANT tOP_ASGN arg
                    {
                        yyerror("constant re-assignment");
                        $$ = 0;
                    }
                | tCOLON3 tCONSTANT tOP_ASGN arg
                    {
                        yyerror("constant re-assignment");
                        $$ = 0;
                    }
                | backref tOP_ASGN arg
                    {
                        rb_backref_error($1);
                        $$ = 0;
                    }
                | arg tDOT2 arg
                    {
                        value_expr($1);
                        value_expr($3);
                        $$ = NEW_DOT2($1, $3);
                    }
                | arg tDOT3 arg
                    {
                        value_expr($1);
                        value_expr($3);
                        $$ = NEW_DOT3($1, $3);
                    }
                | arg '+' arg
                    {
                        $$ = call_op($1, '+', 1, $3, parse_state);
                    }
                | arg '-' arg
                    {
                        $$ = call_op($1, '-', 1, $3, parse_state);
                    }
                | arg '*' arg
                    {
                        $$ = call_op($1, '*', 1, $3, parse_state);
                    }
                | arg '/' arg
                    {
                        $$ = call_op($1, '/', 1, $3, parse_state);
                    }
                | arg '%' arg
                    {
                        $$ = call_op($1, '%', 1, $3, parse_state);
                    }
                | arg tPOW arg
                    {
                        $$ = call_op($1, tPOW, 1, $3, parse_state);
                    }
                | tUMINUS_NUM tINTEGER tPOW arg
                    {
                        $$ = call_op(call_op($2, tPOW, 1, $4, parse_state), tUMINUS, 0, 0, parse_state);
                    }
                | tUMINUS_NUM tFLOAT tPOW arg
                    {
                        $$ = call_op(call_op($2, tPOW, 1, $4, parse_state), tUMINUS, 0, 0, parse_state);
                    }
                | tUPLUS arg
                    {
                        $$ = call_op($2, tUPLUS, 0, 0, parse_state);
                    }
                | tUMINUS arg
                    {
                        $$ = call_op($2, tUMINUS, 0, 0, parse_state);
                    }
                | arg '|' arg
                    {
                        $$ = call_op($1, '|', 1, $3, parse_state);
                    }
                | arg '^' arg
                    {
                        $$ = call_op($1, '^', 1, $3, parse_state);
                    }
                | arg '&' arg
                    {
                        $$ = call_op($1, '&', 1, $3, parse_state);
                    }
                | arg tCMP arg
                    {
                        $$ = call_op($1, tCMP, 1, $3, parse_state);
                    }
                | arg '>' arg
                    {
                        $$ = call_op($1, '>', 1, $3, parse_state);
                    }
                | arg tGEQ arg
                    {
                        $$ = call_op($1, tGEQ, 1, $3, parse_state);
                    }
                | arg '<' arg
                    {
                        $$ = call_op($1, '<', 1, $3, parse_state);
                    }
                | arg tLEQ arg
                    {
                        $$ = call_op($1, tLEQ, 1, $3, parse_state);
                    }
                | arg tEQ arg
                    {
                        $$ = call_op($1, tEQ, 1, $3, parse_state);
                    }
                | arg tEQQ arg
                    {
                        $$ = call_op($1, tEQQ, 1, $3, parse_state);
                    }
                | arg tNEQ arg
                    {
                        $$ = NEW_NOT(call_op($1, tEQ, 1, $3, parse_state));
                    }
                | arg tMATCH arg
                    {
                        $$ = match_gen($1, $3, parse_state);
                    }
                | arg tNMATCH arg
                    {
                        $$ = NEW_NOT(match_gen($1, $3, parse_state));
                    }
                | '!' arg
                    {
                        $$ = NEW_NOT(cond($2, parse_state));
                    }
                | '~' arg
                    {
                        $$ = call_op($2, '~', 0, 0, parse_state);
                    }
                | arg tLSHFT arg
                    {
                        $$ = call_op($1, tLSHFT, 1, $3, parse_state);
                    }
                | arg tRSHFT arg
                    {
                        $$ = call_op($1, tRSHFT, 1, $3, parse_state);
                    }
                | arg tANDOP arg
                    {
                        $$ = logop(NODE_AND, $1, $3, parse_state);
                    }
                | arg tOROP arg
                    {
                        $$ = logop(NODE_OR, $1, $3, parse_state);
                    }
                | kDEFINED opt_nl {vps->in_defined = 1;} arg
                    {
                        vps->in_defined = 0;
                        $$ = NEW_DEFINED($4);
                    }
                | arg '?' {vps->ternary_colon++;} arg ':' arg
                    {
                        $$ = NEW_IF(cond($1, parse_state), $4, $6);
                        fixpos($$, $1);
                        vps->ternary_colon--;
                    }
                | primary
                    {
                        $$ = $1;
                    }
                ;

arg_value       : arg
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                ;

aref_args       : none
                | command opt_nl
                    {
                        rb_warn("parenthesize argument(s) for future version");
                        $$ = NEW_LIST($1);
                    }
                | args trailer
                    {
                        $$ = $1;
                    }
                | args ',' tSTAR arg opt_nl
                    {
                        value_expr($4);
                        $$ = arg_concat(parse_state, $1, $4);
                    }
                | assocs trailer
                    {
                        $$ = NEW_LIST(NEW_HASH($1));
                    }
                | tSTAR arg opt_nl
                    {
                        value_expr($2);
                        $$ = NEW_NEWLINE(NEW_SPLAT($2));
                    }
                ;

paren_args      : '(' none ')'
                    {
                        $$ = $2;
                    }
                | '(' call_args opt_nl ')'
                    {
                        $$ = $2;
                    }
                | '(' block_call opt_nl ')'
                    {
                        rb_warn("parenthesize argument for future version");
                        $$ = NEW_LIST($2);
                    }
                | '(' args ',' block_call opt_nl ')'
                    {
                        rb_warn("parenthesize argument for future version");
                        $$ = list_append(parse_state, $2, $4);
                    }
                ;

opt_paren_args  : none
                | paren_args
                ;

call_args       : command
                    {
                        rb_warn("parenthesize argument(s) for future version");
                        $$ = NEW_LIST($1);
                    }
                | args opt_block_arg
                    {
                        $$ = arg_blk_pass($1, $2);
                    }
                | args ',' tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_concat(parse_state, $1, $4);
                        $$ = arg_blk_pass($$, $5);
                    }
                | assocs opt_block_arg
                    {
                        $$ = NEW_LIST(NEW_POSITIONAL($1));
                        $$ = arg_blk_pass($$, $2);
                    }
                | assocs ',' tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_concat(parse_state, NEW_LIST(NEW_POSITIONAL($1)), $4);
                        $$ = arg_blk_pass($$, $5);
                    }
                | args ',' assocs opt_block_arg
                    {
                        $$ = list_append(parse_state, $1, NEW_POSITIONAL($3));
                        $$ = arg_blk_pass($$, $4);
                    }
                | args ',' assocs ',' tSTAR arg opt_block_arg
                    {
                        value_expr($6);
                        $$ = arg_concat(parse_state, list_append(parse_state, $1, NEW_POSITIONAL($3)), $6);
                        $$ = arg_blk_pass($$, $7);
                    }
                | tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_blk_pass(NEW_SPLAT($2), $3);
                    }
                | block_arg
                ;

call_args2      : arg_value ',' args opt_block_arg
                    {
                        $$ = arg_blk_pass(list_concat(NEW_LIST($1),$3), $4);
                    }
                | arg_value ',' block_arg
                    {
                        $$ = arg_blk_pass($1, $3);
                    }
                | arg_value ',' tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_concat(parse_state, NEW_LIST($1), $4);
                        $$ = arg_blk_pass($$, $5);
                    }
                | arg_value ',' args ',' tSTAR arg_value opt_block_arg
                    {
            $$ = arg_concat(parse_state, list_concat(NEW_LIST($1),$3), $6);
                        $$ = arg_blk_pass($$, $7);
                    }
                | assocs opt_block_arg
                    {
                        $$ = NEW_LIST(NEW_POSITIONAL($1));
                        $$ = arg_blk_pass($$, $2);
                    }
                | assocs ',' tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_concat(parse_state, NEW_LIST(NEW_POSITIONAL($1)), $4);
                        $$ = arg_blk_pass($$, $5);
                    }
                | arg_value ',' assocs opt_block_arg
                    {
                        $$ = list_append(parse_state, NEW_LIST($1), NEW_POSITIONAL($3));
                        $$ = arg_blk_pass($$, $4);
                    }
                | arg_value ',' args ',' assocs opt_block_arg
                    {
                        $$ = list_append(parse_state, list_concat(NEW_LIST($1),$3), NEW_POSITIONAL($5));
                        $$ = arg_blk_pass($$, $6);
                    }
                | arg_value ',' assocs ',' tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_concat(parse_state, list_append(parse_state, NEW_LIST($1), NEW_POSITIONAL($3)), $6);
                        $$ = arg_blk_pass($$, $7);
                    }
                | arg_value ',' args ',' assocs ',' tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_concat(parse_state, list_append(parse_state, list_concat(NEW_LIST($1), $3), NEW_POSITIONAL($5)), $8);
                        $$ = arg_blk_pass($$, $9);
                    }
                | tSTAR arg_value opt_block_arg
                    {
                        $$ = arg_blk_pass(NEW_SPLAT($2), $3);
                    }
                | block_arg
                ;

command_args    :  {
                        $<num>$ = vps->cmdarg_stack;
                        CMDARG_PUSH(1);
                    }
                  open_args
                    {
                        /* CMDARG_POP() */
                        vps->cmdarg_stack = $<num>1;
                        $$ = $2;
                    }
                ;

open_args       : call_args
                | tLPAREN_ARG  {vps->lex_state = EXPR_ENDARG;} ')'
                    {
                        rb_warn("don't put space before argument parentheses");
                        $$ = 0;
                    }
                | tLPAREN_ARG call_args2 {vps->lex_state = EXPR_ENDARG;} ')'
                    {
                        rb_warn("don't put space before argument parentheses");
                        $$ = $2;
                    }
                ;

block_arg       : tAMPER arg_value
                    {
                        $$ = NEW_BLOCK_PASS($2);
                    }
                ;

opt_block_arg   : ',' block_arg
                    {
                        $$ = $2;
                    }
                | none
                ;

args            : arg_value
                    {
                        $$ = NEW_LIST($1);
                    }
                | args ',' arg_value
                    {
                        $$ = list_append(parse_state, $1, $3);
                    }
                ;

mrhs            : args ',' arg_value
                    {
                        $$ = list_append(parse_state, $1, $3);
                    }
                | args ',' tSTAR arg_value
                    {
                        $$ = arg_concat(parse_state, $1, $4);
                    }
                | tSTAR arg_value
                    {
                        $$ = NEW_SPLAT($2);
                    }
                ;

primary         : literal
                | strings
                | xstring
                | regexp
                | words
                | qwords
                | var_ref
                | backref
                | tFID
                    {
                        $$ = NEW_FCALL($1, 0);
                    }
                | kBEGIN
                    {
                        $<num>1 = ruby_sourceline;
                    }
                  bodystmt
                  kEND
                    {
                        if ($3 == NULL)
                            $$ = NEW_NIL();
                        else
                            $$ = NEW_BEGIN($3);
                        nd_set_line($$, $<num>1);
                    }
                | tLPAREN_ARG expr {vps->lex_state = EXPR_ENDARG;} opt_nl ')'
                    {
                        rb_warning("(...) interpreted as grouped expression");
                        $$ = $2;
                    }
                | tLPAREN compstmt ')'
                    {
                        $$ = $2;
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                        $$ = NEW_COLON2($1, $3);
                    }
                | tCOLON3 tCONSTANT
                    {
                        $$ = NEW_COLON3($2);
                    }
                | primary_value '[' aref_args ']'
                    {
                        if ($1 && nd_type($1) == NODE_SELF) {
                            $$ = NEW_FCALL(convert_op(tAREF), $3);
                        } else {
                            $$ = NEW_CALL($1, convert_op(tAREF), $3);
                        }
                        fixpos($$, $1);
                    }
                | tLBRACK aref_args ']'
                    {
                        if ($2 == 0) {
                            $$ = NEW_ZARRAY(); /* zero length array*/
                        }
                        else {
                            $$ = $2;
                        }
                    }
                | tLBRACE assoc_list '}'
                    {
                        $$ = NEW_HASH($2);
                    }
                | kRETURN
                    {
                        $$ = NEW_RETURN(0);
                    }
                | kYIELD '(' call_args ')'
                    {
                        $$ = new_yield(parse_state, $3);
                    }
                | kYIELD '(' ')'
                    {
                        $$ = NEW_YIELD(0, Qfalse);
                    }
                | kYIELD
                    {
                        $$ = NEW_YIELD(0, Qfalse);
                    }
                | kDEFINED opt_nl '(' {vps->in_defined = 1;} expr ')'
                    {
                        vps->in_defined = 0;
                        $$ = NEW_DEFINED($5);
                    }
                | operation brace_block
                    {
                        $2->nd_iter = NEW_FCALL($1, 0);
                        $$ = $2;
                        fixpos($2->nd_iter, $2);
                    }
                | method_call
                | method_call brace_block
                    {
                        if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
                            rb_compile_error("both block arg and actual block given");
                        }
                        $2->nd_iter = $1;
                        $$ = $2;
                        fixpos($$, $1);
                    }
                | kIF expr_value then
                  compstmt
                  if_tail
                  kEND
                    {
                        $$ = NEW_IF(cond($2, parse_state), $4, $5);
                        fixpos($$, $2);
                        if (cond_negative(&$$->nd_cond)) {
                            NODE *tmp = $$->nd_body;
                            $$->nd_body = $$->nd_else;
                            $$->nd_else = tmp;
                        }
                    }
                | kUNLESS expr_value then
                  compstmt
                  opt_else
                  kEND
                    {
                        $$ = NEW_UNLESS(cond($2, parse_state), $4, $5);
                        fixpos($$, $2);
                        if (cond_negative(&$$->nd_cond)) {
                            NODE *tmp = $$->nd_body;
                            $$->nd_body = $$->nd_else;
                            $$->nd_else = tmp;
                        }
                    }
                | kWHILE {COND_PUSH(1);} expr_value do {COND_POP();}
                  compstmt
                  kEND
                    {
                        $$ = NEW_WHILE(cond($3, parse_state), $6, 1);
                        fixpos($$, $3);
                        if (cond_negative(&$$->nd_cond)) {
                            nd_set_type($$, NODE_UNTIL);
                        }
                    }
                | kUNTIL {COND_PUSH(1);} expr_value do {COND_POP();} 
                  compstmt
                  kEND
                    {
                        $$ = NEW_UNTIL(cond($3, parse_state), $6, 1);
                        fixpos($$, $3);
                        if (cond_negative(&$$->nd_cond)) {
                            nd_set_type($$, NODE_WHILE);
                        }
                    }
                | kCASE expr_value opt_terms
                  case_body
                  kEND
                    {
                        $$ = NEW_CASE($2, $4);
                        fixpos($$, $2);
                    }
                | kCASE opt_terms case_body kEND
                    {
                        $$ = $3;
                    }
                | kCASE opt_terms kELSE compstmt kEND
                    {
                        $$ = $4;
                    }
                | kFOR block_var kIN {COND_PUSH(1);} expr_value do {COND_POP();}
                  compstmt
                  kEND
                    {
                        $$ = NEW_FOR($2, $5, $8);
                        fixpos($$, $2);
                    }
                | kCLASS cpath superclass
                    {
                        if (in_def || in_single)
                            yyerror("class definition in method body");
                        class_nest++;
                        local_push(0);
                        $<num>$ = ruby_sourceline;
                    }
                  bodystmt
                  kEND
                    {
                        $$ = NEW_CLASS($2, $5, $3);
                        nd_set_line($$, $<num>4);
                        local_pop();
                        class_nest--;
                    }
                | kCLASS tLSHFT expr
                    {
                        $<num>$ = in_def;
                        in_def = 0;
                    }
                  term
                    {
                        $<num>$ = in_single;
                        in_single = 0;
                        class_nest++;
                        local_push(0);
                    }
                  bodystmt
                  kEND
                    {
                        $$ = NEW_SCLASS($3, $7);
                        fixpos($$, $3);
                        local_pop();
                        class_nest--;
                        in_def = $<num>4;
                        in_single = $<num>6;
                    }
                | kMODULE cpath
                    {
                        if (in_def || in_single)
                            yyerror("module definition in method body");
                        class_nest++;
                        local_push(0);
                        $<num>$ = ruby_sourceline;
                    }
                  bodystmt
                  kEND
                    {
                        $$ = NEW_MODULE($2, $4);
                        nd_set_line($$, $<num>3);
                        local_pop();
                        class_nest--;
                    }
                | kDEF fname
                    {
                        $<id>$ = cur_mid;
                        cur_mid = $2;
                        in_def++;
                        local_push(0);
                    }
                  f_arglist
                  bodystmt
                  kEND
                    {
                        if (!$5) $5 = NEW_NIL();
                        $$ = NEW_DEFN($2, $4, $5, NOEX_PRIVATE);
                        fixpos($$, $4);
                        local_pop();
                        in_def--;
                        cur_mid = $<id>3;
                    }
                | kDEF singleton dot_or_colon {vps->lex_state = EXPR_FNAME;} fname
                    {
                        in_single++;
                        local_push(0);
                        vps->lex_state = EXPR_END; /* force for args */
                    }
                  f_arglist
                  bodystmt
                  kEND
                    {
                        $$ = NEW_DEFS($2, $5, $7, $8);
                        fixpos($$, $2);
                        local_pop();
                        in_single--;
                    }
                | kBREAK
                    {
                        $$ = NEW_BREAK(0);
                    }
                | kNEXT
                    {
                        $$ = NEW_NEXT(0);
                    }
                | kREDO
                    {
                        $$ = NEW_REDO();
                    }
                | kRETRY
                    {
                        $$ = NEW_RETRY();
                    }
                ;

primary_value   : primary
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                ;

then            : term
                | ':'
                | kTHEN
                | term kTHEN
                ;

do              : term
                | ':'
                | kDO_COND
                ;

if_tail         : opt_else
                | kELSIF expr_value then
                  compstmt
                  if_tail
                    {
                        $$ = NEW_IF(cond($2, parse_state), $4, $5);
                        fixpos($$, $2);
                    }
                ;

opt_else        : none
                | kELSE compstmt
                    {
                        $$ = $2;
                    }
                ;

block_var       : lhs
                | mlhs
                ;

opt_block_var   : none
                | '|' /* none */ '|'
                    {
                        $$ = (NODE*)1;
                    }
                | tOROP
                    {
                        $$ = (NODE*)1;
                    }
                | '|' block_var '|'
                    {
                        $$ = $2;
                    }
                ;

do_block        : kDO_BLOCK
                    {
                        $<num>1 = ruby_sourceline;
                        reset_block(vps);
                    }
                  opt_block_var
                    {
                      $<vars>$ = vps->block_vars;
                    }
                  compstmt
                  kEND
                    {
                        $$ = NEW_ITER($3, 0, extract_block_vars(vps, $5, $<vars>4));
                        nd_set_line($$, $<num>1);
                    }
                ;

block_call      : command do_block
                    {
                        if ($1 && nd_type($1) == NODE_BLOCK_PASS) {
                            rb_compile_error("both block arg and actual block given");
                        }
                        $2->nd_iter = $1;
                        $$ = $2;
                        fixpos($$, $1);
                    }
                | block_call '.' operation2 opt_paren_args
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                    }
                | block_call tCOLON2 operation2 opt_paren_args
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                    }
                ;

method_call     : operation paren_args
                    {
                        $$ = new_fcall(parse_state, $1, $2);
                        fixpos($$, $2);
                    }
                | primary_value '.' operation2 opt_paren_args
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                        fixpos($$, $1);
                    }
                | primary_value tCOLON2 operation2 paren_args
                    {
                        $$ = new_call(parse_state, $1, $3, $4);
                        fixpos($$, $1);
                    }
                | primary_value tCOLON2 operation3
                    {
                        $$ = new_call(parse_state, $1, $3, 0);
                    }
                | primary_value '\\' operation2
                    {
                        $$ = NEW_CALL($1, rb_intern("get_reference"), NEW_LIST(NEW_LIT(ID2SYM($3))));
                    }
                | tUBS operation2
                    {
                        $$ = NEW_FCALL(rb_intern("get_reference"), NEW_LIST(NEW_LIT(ID2SYM($2))));
                    }
                | kSUPER paren_args
                    {
                        $$ = new_super(parse_state, $2);
                    }
                | kSUPER
                    {
                        $$ = NEW_ZSUPER();
                    }
                ;

brace_block     : '{'
                    {
                        $<num>1 = ruby_sourceline;
                        reset_block(vps);
                    }
                  opt_block_var { $<vars>$ = vps->block_vars; }
                  compstmt '}'
                    {
                        $$ = NEW_ITER($3, 0, extract_block_vars(vps, $5, $<vars>4));
                        nd_set_line($$, $<num>1);
                    }
                | kDO
                    {
                        $<num>1 = ruby_sourceline;
                        reset_block(vps);
                    }
                  opt_block_var { $<vars>$ = vps->block_vars; }
                  compstmt kEND
                    {
                        $$ = NEW_ITER($3, 0, extract_block_vars(vps, $5, $<vars>4));
                        nd_set_line($$, $<num>1);
                    }
                ;

case_body       : kWHEN when_args then
                  compstmt
                  cases
                    {
                        $$ = NEW_WHEN($2, $4, $5);
                    }
                ;
when_args       : args
                | args ',' tSTAR arg_value
                    {
                        $$ = list_append(parse_state, $1, NEW_WHEN($4, 0, 0));
                    }
                | tSTAR arg_value
                    {
                        $$ = NEW_LIST(NEW_WHEN($2, 0, 0));
                    }
                ;

cases           : opt_else
                | case_body
                ;

opt_rescue      : kRESCUE exc_list exc_var then
                  compstmt
                  opt_rescue
                    {
                        if ($3) {
                            $3 = node_assign($3, NEW_GVAR(rb_intern("$!")), parse_state);
                            $5 = block_append(parse_state, $3, $5);
                        }
                        $$ = NEW_RESBODY($2, $5, $6);
                        fixpos($$, $2?$2:$5);
                    }
                | none
                ;

exc_list        : arg_value
                    {
                        $$ = NEW_LIST($1);
                    }
                | mrhs
                | none
                ;

exc_var         : tASSOC lhs
                    {
                        $$ = $2;
                    }
                | none
                ;

opt_ensure      : kENSURE compstmt
                    {
                        if ($2)
                            $$ = $2;
                        else
                            /* place holder */
                            $$ = NEW_NIL();
                    }
                | none
                ;

literal         : numeric
                | symbol
                    {
                        $$ = NEW_LIT(ID2SYM($1));
                    }
                | dsym
                ;

strings         : string
                    {
                        NODE *node = $1;
                        if (!node) {
                            node = NEW_STR(string_new(0, 0));
                        }
                        else {
                            node = evstr2dstr(parse_state, node);
                        }
                        $$ = node;
                    }
                ;

string          : string1
                | string string1
                    {
                        $$ = literal_concat(parse_state, $1, $2);
                    }
                ;

string1         : tSTRING_BEG string_contents tSTRING_END
                    {
                        $$ = $2;
                    }
                ;

xstring         : tXSTRING_BEG xstring_contents tSTRING_END
                    {
                        ID code = $1;
                        NODE *node = $2;
                        if (!node) {
                            node = NEW_XSTR(string_new(0, 0));
                        }
                        else {
                            switch (nd_type(node)) {
                              case NODE_STR:
                                nd_set_type(node, NODE_XSTR);
                                break;
                              case NODE_DSTR:
                                nd_set_type(node, NODE_DXSTR);
                                break;
                              default:
                                node = NEW_NODE(NODE_DXSTR, string_new(0, 0), 1, NEW_LIST(node));
                                break;
                            }
                        }
                        if(code) {
                            node->u2.id = code;
                        } else {
                            node->u2.id = 0;
                        }
                        $$ = node;
                    }
                ;

regexp          : tREGEXP_BEG xstring_contents tREGEXP_END
                    {
                        intptr_t options = $3;
                        NODE *node = $2;
                        if (!node) {
                            node = NEW_REGEX(string_new2(""), options & ~RE_OPTION_ONCE);
                        }
                        else switch (nd_type(node)) {
                          case NODE_STR:
                            {
                                nd_set_type(node, NODE_REGEX);
                                node->nd_cnt = options & ~RE_OPTION_ONCE;
                                /*
                                node->nd_lit = rb_reg_new(RSTRING(src)->ptr,
                                                          RSTRING(src)->len,
                                                          options & ~RE_OPTION_ONCE);
                                */
                            }
                            break;
                          default:
                            node = NEW_NODE(NODE_DSTR, string_new(0, 0), 1, NEW_LIST(node));
                          case NODE_DSTR:
                            if (options & RE_OPTION_ONCE) {
                                nd_set_type(node, NODE_DREGX_ONCE);
                            }
                            else {
                                nd_set_type(node, NODE_DREGX);
                            }
                            node->nd_cflag = options & ~RE_OPTION_ONCE;
                            break;
                        }
                        $$ = node;
                    }
                ;

words           : tWORDS_BEG ' ' tSTRING_END
                    {
                        $$ = NEW_ZARRAY();
                    }
                | tWORDS_BEG word_list tSTRING_END
                    {
                        $$ = $2;
                    }
                ;

word_list       : /* none */
                    {
                        $$ = 0;
                    }
                | word_list word ' '
                    {
                        $$ = list_append(parse_state, $1, evstr2dstr(parse_state, $2));
                    }
                ;

word            : string_content
                | word string_content
                    {
                        $$ = literal_concat(parse_state, $1, $2);
                    }
                ;

qwords          : tQWORDS_BEG ' ' tSTRING_END
                    {
                        $$ = NEW_ZARRAY();
                    }
                | tQWORDS_BEG qword_list tSTRING_END
                    {
                        $$ = $2;
                    }
                ;

qword_list      : /* none */
                    {
                        $$ = 0;
                    }
                | qword_list tSTRING_CONTENT ' '
                    {
                        $$ = list_append(parse_state, $1, $2);
                    }
                ;

string_contents : /* none */
                    {
                        $$ = 0;
                    }
                | string_contents string_content
                    {
                        $$ = literal_concat(parse_state, $1, $2);
                    }
                ;

xstring_contents: /* none */
                    {
                        $$ = 0;
                    }
                | xstring_contents string_content
                    {
                        $$ = literal_concat(parse_state, $1, $2);
                    }
                ;

string_content  : tSTRING_CONTENT
                | tSTRING_DVAR
                    {
                        $<node>$ = lex_strterm;
                        lex_strterm = 0;
                        vps->lex_state = EXPR_BEG;
                    }
                  string_dvar
                    {
                        lex_strterm = $<node>2;
                        $$ = NEW_EVSTR($3);
                    }
                | tSTRING_DBEG
                    {
                        $<node>$ = lex_strterm;
                        lex_strterm = 0;
                        vps->lex_state = EXPR_BEG;
                        COND_PUSH(0);
                        CMDARG_PUSH(0);
                    }
                  compstmt '}'
                    {
                        lex_strterm = $<node>2;
                        COND_LEXPOP();
                        CMDARG_LEXPOP();
                        if (($$ = $3) && nd_type($$) == NODE_NEWLINE) {
                            $$ = $$->nd_next;
                        }
                        $$ = new_evstr(parse_state, $$);
                    }
                ;

string_dvar     : tGVAR {$$ = NEW_GVAR($1);}
                | tIVAR {$$ = NEW_IVAR($1);}
                | tCVAR {$$ = NEW_CVAR($1);}
                | backref
                ;

symbol          : tSYMBEG sym
                    {
                        vps->lex_state = EXPR_END;
                        $$ = $2;
                    }
                ;

sym             : fname
                | tIVAR
                | tGVAR
                | tCVAR
                ;

dsym            : tSYMBEG xstring_contents tSTRING_END
                    {
                        vps->lex_state = EXPR_END;
                        if (!($$ = $2)) {
                            yyerror("empty symbol literal");
                        }
                        else {
                            switch (nd_type($$)) {
                              case NODE_DSTR:
                                nd_set_type($$, NODE_DSYM);
                                break;
                              case NODE_STR:
                                /* TODO: this line should never fail unless nd_str is binary */
                                if (strlen(bdatae($$->nd_str,"")) == blength($$->nd_str)) {
                                  ID tmp = rb_intern(bdata($$->nd_str));
                                  bdestroy($$->nd_str);
                                  $$->nd_lit = ID2SYM(tmp);
                                  nd_set_type($$, NODE_LIT);
                                  break;
                                } else {
                                  bdestroy($$->nd_str);
                                }
                                /* fall through */
                              default:
                                $$ = NEW_NODE(NODE_DSYM, string_new(0, 0), 1, NEW_LIST($$));
                                break;
                            }
                        }
                    }
                ;

numeric         : tINTEGER
                | tFLOAT
                | tUMINUS_NUM tINTEGER         %prec tLOWEST
                    {
                        $$ = NEW_NEGATE($2);
                    }
                | tUMINUS_NUM tFLOAT           %prec tLOWEST
                    {
                        $$ = NEW_NEGATE($2);
                    }
                ;

variable        : tIDENTIFIER
                | tIVAR
                | tGVAR
                | tCONSTANT
                | tCVAR
                | kNIL {$$ = kNIL;}
                | kSELF {$$ = kSELF;}
                | kTRUE {$$ = kTRUE;}
                | kFALSE {$$ = kFALSE;}
                | k__FILE__ {$$ = k__FILE__;}
                | k__LINE__ {$$ = k__LINE__;}
                ;

var_ref         : variable
                    {
                        $$ = gettable($1);
                    }
                ;

var_lhs         : variable
                    {
                        $$ = assignable($1, 0, parse_state);
                    }
                ;

backref         : tNTH_REF
                | tBACK_REF
                ;

superclass      : term
                    {
                        $$ = 0;
                    }
                | '<'
                    {
                        vps->lex_state = EXPR_BEG;
                    }
                  expr_value term
                    {
                        $$ = $3;
                    }
                | error term {yyerrok; $$ = 0;}
                ;

f_arglist       : '(' f_args opt_nl ')'
                    {
                        $$ = $2;
                        vps->lex_state = EXPR_BEG;
                    }
                | f_args term
                    {
                        $$ = $1;
                    }
                ;

f_args          : f_arg ',' f_optarg ',' f_rest_arg opt_f_block_arg
                    {
		      $$ = block_append(parse_state, NEW_ARGS((intptr_t)$1, $3, $5), $6);
                    }
                | f_arg ',' f_optarg opt_f_block_arg
                    {
		      $$ = block_append(parse_state, NEW_ARGS((intptr_t)$1, $3, -1), $4);
                    }
                | f_arg ',' f_rest_arg opt_f_block_arg
                    {
		      $$ = block_append(parse_state, NEW_ARGS((intptr_t)$1, 0, $3), $4);
                    }
                | f_arg opt_f_block_arg
                    {
		      $$ = block_append(parse_state, NEW_ARGS((intptr_t)$1, 0, -1), $2);
                    }
                | f_optarg ',' f_rest_arg opt_f_block_arg
                    {
                        $$ = block_append(parse_state, NEW_ARGS(0, $1, $3), $4);
                    }
                | f_optarg opt_f_block_arg
                    {
                        $$ = block_append(parse_state, NEW_ARGS(0, $1, -1), $2);
                    }
                | f_rest_arg opt_f_block_arg
                    {
                        $$ = block_append(parse_state, NEW_ARGS(0, 0, $1), $2);
                    }
                | f_block_arg
                    {
                        $$ = block_append(parse_state, NEW_ARGS(0, 0, -1), $1);
                    }
                | /* none */
                    {
                        $$ = NEW_ARGS(0, 0, -1);
                    }
                ;

f_norm_arg      : tCONSTANT
                    {
                        yyerror("formal argument cannot be a constant");
                    }
                | tIVAR
                    {
                        yyerror("formal argument cannot be an instance variable");
                    }
                | tGVAR
                    {
                        yyerror("formal argument cannot be a global variable");
                    }
                | tCVAR
                    {
                        yyerror("formal argument cannot be a class variable");
                    }
                | tIDENTIFIER
                    {
                        if (!is_local_id($1))
                            yyerror("formal argument must be local variable");
                        else if (local_id($1))
                            yyerror("duplicate argument name");
                        local_cnt($1);
                        $$ = 1;
                    }
                ;

f_arg           : f_norm_arg
                | f_arg ',' f_norm_arg
                    {
                        $$ += 1;
                    }
                ;

f_opt           : tIDENTIFIER '=' arg_value
                    {
                        if (!is_local_id($1))
                            yyerror("formal argument must be local variable");
                        else if (local_id($1))
                            yyerror("duplicate optional argument name");
                        $$ = assignable($1, $3, parse_state);
                    }
                ;

f_optarg        : f_opt
                    {
                        $$ = NEW_BLOCK($1);
                        $$->nd_end = $$;
                    }
                | f_optarg ',' f_opt
                    {
                        $$ = block_append(parse_state, $1, $3);
                    }
                ;

restarg_mark    : '*'
                | tSTAR
                ;

f_rest_arg      : restarg_mark tIDENTIFIER
                    {
                        if (!is_local_id($2))
                            yyerror("rest argument must be local variable");
                        else if (local_id($2))
                            yyerror("duplicate rest argument name");
                        $$ = local_cnt($2) + 1;
                    }
                | restarg_mark
                    {
                        $$ = 0;
                    }
                ;

blkarg_mark     : '&'
                | tAMPER
                ;

f_block_arg     : blkarg_mark tIDENTIFIER
                    {
                        if (!is_local_id($2))
                            yyerror("block argument must be local variable");
                        else if (local_id($2))
                            yyerror("duplicate block argument name");
                        $$ = NEW_BLOCK_ARG($2);
                    }
                ;

opt_f_block_arg : ',' f_block_arg
                    {
                        $$ = $2;
                    }
                | none
                ;

singleton       : var_ref
                    {
                        if (nd_type($1) == NODE_SELF) {
                            $$ = NEW_SELF();
                        }
                        else {
                            $$ = $1;
                            value_expr($$);
                        }
                    }
                | '(' {vps->lex_state = EXPR_BEG;} expr opt_nl ')'
                    {
                        if ($3 == 0) {
                            yyerror("can't define singleton method for ().");
                        }
                        else {
                            switch (nd_type($3)) {
                              case NODE_STR:
                              case NODE_DSTR:
                              case NODE_XSTR:
                              case NODE_DXSTR:
                              case NODE_DREGX:
                              case NODE_LIT:
                              case NODE_ARRAY:
                              case NODE_ZARRAY:
                                yyerror("can't define singleton method for literals");
                              default:
                                value_expr($3);
                                break;
                            }
                        }
                        $$ = $3;
                    }
                ;

assoc_list      : none
                | assocs trailer
                    {
                        $$ = $1;
                    }
                | args trailer
                    {
                        if ($1->nd_alen%2 != 0) {
                            yyerror("odd number list for Hash");
                        }
                        $$ = $1;
                    }
                ;

assocs          : assoc
                | assocs ',' assoc
                    {
                        $$ = list_concat($1, $3);
                    }
                ;

assoc           : arg_value tASSOC arg_value
                    {
                        $$ = list_append(parse_state, NEW_LIST($1), $3);
                    }
                ;

operation       : tIDENTIFIER
                | tCONSTANT
                | tFID
                ;

operation2      : tIDENTIFIER
                | tCONSTANT
                | tFID
                | op
                ;

operation3      : tIDENTIFIER
                | tFID
                | op
                ;

dot_or_colon    : '.'
                | tCOLON2
                ;

opt_terms       : /* none */
                | terms
                ;

opt_nl          : /* none */
                | '\n'
                ;

trailer         : /* none */
                | '\n'
                | ','
                ;

term            : ';' {yyerrok;}
                | '\n'
                ;

terms           : term
                | terms ';' {yyerrok;}
                ;

none            : /* none */ {$$ = 0;}
                ;
%%

/* We remove any previous definition of `SIGN_EXTEND_CHAR',
   since ours (we hope) works properly with all combinations of
   machines, compilers, `char' and `unsigned char' argument types.
   (Per Bothner suggested the basic approach.)  */
#undef SIGN_EXTEND_CHAR
#if __STDC__
# define SIGN_EXTEND_CHAR(c) ((signed char)(c))
#else  /* not __STDC__ */
/* As in Harbison and Steele.  */
# define SIGN_EXTEND_CHAR(c) ((((unsigned char)(c)) ^ 128) - 128)
#endif
#define is_identchar(c) (SIGN_EXTEND_CHAR(c)!=-1&&(ISALNUM(c) || (c) == '_' || ismbchar(c)))

#define LEAVE_BS 1

static int
syd_yyerror(msg, parse_state)
    const char *msg;
    rb_parse_state *parse_state;
{
    create_error(parse_state, (char *)msg);

    return 1;
}

static int
yycompile(parse_state, f, line)
    rb_parse_state *parse_state;
    char *f;
    int line;
{
    int n;
    /* Setup an initial empty scope. */
    heredoc_end = 0;
    lex_strterm = 0;
    ruby_sourcefile = f;
    n = yyparse(parse_state);
    ruby_debug_lines = 0;
    compile_for_eval = 0;
    parse_state->cond_stack = 0;
    parse_state->cmdarg_stack = 0;
    command_start = TRUE;
    class_nest = 0;
    in_single = 0;
    in_def = 0;
    cur_mid = 0;

    lex_strterm = 0;

    return n;
}

static bool
lex_get_str(rb_parse_state *parse_state)
{
    const char *str;
    const char *beg, *end, *pend;
    int sz;

    str = bdata(parse_state->lex_string);
    beg = str;
    
    if (parse_state->lex_str_used) {
      if (blength(parse_state->lex_string) == parse_state->lex_str_used) {
        return false;
      }

      beg += parse_state->lex_str_used;
    }
    
    pend = str + blength(parse_state->lex_string);
    end = beg;
    
    while(end < pend) {
      if(*end++ == '\n') break;
    }
    
    sz = end - beg;
    bcatblk(parse_state->line_buffer, beg, sz);
    parse_state->lex_str_used += sz;

    return TRUE;
}

void syd_add_to_parse_tree(STATE, OBJECT ary,
      NODE * n, int newlines, ID * locals, int line_numbers);

static OBJECT convert_to_sexp(STATE, NODE *node, int newlines) {
  OBJECT ary;
  ary = array_new(state, 1);
  syd_add_to_parse_tree(state, ary, node, newlines, NULL, FALSE);
  return array_get(state, ary, 0);
}

static bool
lex_getline(rb_parse_state *parse_state)
{
  if(!parse_state->line_buffer) {
    parse_state->line_buffer = cstr2bstr("");
  } else {
    btrunc(parse_state->line_buffer, 0);
  }

  return parse_state->lex_gets(parse_state);
}

OBJECT
syd_compile_string(STATE, const char *f, bstring s, int line, int newlines)
{
    int n;
    rb_parse_state *parse_state;
    OBJECT ret;
    parse_state = alloc_parse_state();
    parse_state->state = state;
    parse_state->lex_string = s;
    parse_state->lex_gets = lex_get_str;
    parse_state->lex_pbeg = 0;
    parse_state->lex_p = 0;
    parse_state->lex_pend = 0;
    parse_state->error = Qfalse;
    ruby_sourceline = line - 1;
    compile_for_eval = 1;
    
    n = yycompile(parse_state, f, line);
    
    if(parse_state->error == Qfalse) {
        ret = convert_to_sexp(state, parse_state->top, newlines);
    } else {
        ret = parse_state->error;
    }
    pt_free(parse_state);
    free(parse_state);
    return ret;
}

static bool parse_io_gets(rb_parse_state *parse_state) {
  if(feof(parse_state->lex_io)) {
    return false;
  }

  while(TRUE) {
    char *ptr, buf[1024];
    int read;

    ptr = fgets(buf, sizeof(buf), parse_state->lex_io);
    if(!ptr) {
      return false;
    }

    read = strlen(ptr);
    bcatblk(parse_state->line_buffer, ptr, read);

    /* check whether we read a full line */
    if(!(read == (sizeof(buf) - 1) && ptr[read] != '\n')) {
      break;
    }
  }

  return TRUE;
}

OBJECT
syd_compile_file(STATE, const char *f, FILE *file, int start, int newlines)
{
    int n;
    OBJECT ret;
    rb_parse_state *parse_state;
    parse_state = alloc_parse_state();
    parse_state->state = state;
    parse_state->lex_io = file;
    parse_state->lex_gets = parse_io_gets;
    parse_state->lex_pbeg = 0;
    parse_state->lex_p = 0;
    parse_state->lex_pend = 0;
    parse_state->error = Qfalse;
    ruby_sourceline = start - 1;

    n = yycompile(parse_state, f, start);
    
    if(parse_state->error == Qfalse) {
        ret = convert_to_sexp(state, parse_state->top, newlines);
    } else {
        ret = parse_state->error;
    }
    
    pt_free(parse_state);
    free(parse_state);
    return ret;
}

#define nextc() ps_nextc(parse_state)

static inline int
ps_nextc(rb_parse_state *parse_state)
{
    int c;

    if (parse_state->lex_p == parse_state->lex_pend) {
        bstring v;
        
        if (!lex_getline(parse_state)) return -1;
        v = parse_state->line_buffer;

        if (heredoc_end > 0) {
            ruby_sourceline = heredoc_end;
            heredoc_end = 0;
        }
        ruby_sourceline++;
       
        /* This code is setup so that lex_pend can be compared to
           the data in lex_lastline. Thats important, otherwise
           the heredoc code breaks. */
        if(parse_state->lex_lastline) {
          bassign(parse_state->lex_lastline, v);
        } else {
          parse_state->lex_lastline = bstrcpy(v);
        }

        v = parse_state->lex_lastline;

        parse_state->lex_pbeg = parse_state->lex_p = bdata(v);
        parse_state->lex_pend = parse_state->lex_p + blength(v);
    }
    c = (unsigned char)*(parse_state->lex_p++);
    if (c == '\r' && parse_state->lex_p < parse_state->lex_pend && *(parse_state->lex_p) == '\n') {
        parse_state->lex_p++;
        c = '\n';
        parse_state->column = 0;
    } else if(c == '\n') {
        parse_state->column = 0;
    } else {
        parse_state->column++;
    }

    return c;
}

static void
pushback(c, parse_state)
    int c;
    rb_parse_state *parse_state;
{
    if (c == -1) return;
    parse_state->lex_p--;
}

/* Indicates if we're currently at the beginning of a line. */
#define was_bol() (parse_state->lex_p == parse_state->lex_pbeg + 1)
#define peek(c) (parse_state->lex_p != parse_state->lex_pend && (c) == *(parse_state->lex_p))

/* The token buffer. It's just a global string that has
   functions to build up the string easily. */

#define tokfix() (tokenbuf[tokidx]='\0')
#define tok() tokenbuf
#define toklen() tokidx
#define toklast() (tokidx>0?tokenbuf[tokidx-1]:0)

static char*
newtok(rb_parse_state *parse_state)
{
    tokidx = 0;
    if (!tokenbuf) {
        toksiz = 60;
        tokenbuf = ALLOC_N(char, 60);
    }
    if (toksiz > 4096) {
        toksiz = 60;
        REALLOC_N(tokenbuf, char, 60);
    }
    return tokenbuf;
}

static void tokadd(char c, rb_parse_state *parse_state)
{
    assert(tokidx < toksiz && tokidx >= 0);
    tokenbuf[tokidx++] = c;
    if (tokidx >= toksiz) {
        toksiz *= 2;
        REALLOC_N(tokenbuf, char, toksiz);
    }
}

static int
read_escape(rb_parse_state *parse_state)
{
    int c;

    switch (c = nextc()) {
      case '\\':        /* Backslash */
        return c;

      case 'n': /* newline */
        return '\n';

      case 't': /* horizontal tab */
        return '\t';

      case 'r': /* carriage-return */
        return '\r';

      case 'f': /* form-feed */
        return '\f';

      case 'v': /* vertical tab */
        return '\13';

      case 'a': /* alarm(bell) */
        return '\007';

      case 'e': /* escape */
        return 033;

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
        {
            int numlen;

            pushback(c, parse_state);
            c = scan_oct(parse_state->lex_p, 3, &numlen);
            parse_state->lex_p += numlen;
        }
        return c;

      case 'x': /* hex constant */
        {
            int numlen;

            c = scan_hex(parse_state->lex_p, 2, &numlen);
            if (numlen == 0) {
                yyerror("Invalid escape character syntax");
                return 0;
            }
            parse_state->lex_p += numlen;
        }
        return c;

      case 'b': /* backspace */
        return '\010';

      case 's': /* space */
        return ' ';

      case 'M':
        if ((c = nextc()) != '-') {
            yyerror("Invalid escape character syntax");
            pushback(c, parse_state);
            return '\0';
        }
        if ((c = nextc()) == '\\') {
            return read_escape(parse_state) | 0x80;
        }
        else if (c == -1) goto eof;
        else {
            return ((c & 0xff) | 0x80);
        }

      case 'C':
        if ((c = nextc()) != '-') {
            yyerror("Invalid escape character syntax");
            pushback(c, parse_state);
            return '\0';
        }
      case 'c':
        if ((c = nextc())== '\\') {
            c = read_escape(parse_state);
        }
        else if (c == '?')
            return 0177;
        else if (c == -1) goto eof;
        return c & 0x9f;

      eof:
      case -1:
        yyerror("Invalid escape character syntax");
        return '\0';

      default:
        return c;
    }
}

static int
tokadd_escape(term, parse_state)
    int term;
    rb_parse_state *parse_state;
{
    int c;

    switch (c = nextc()) {
      case '\n':
        return 0;               /* just ignore */

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
        {
            int i;

            tokadd((char)'\\', parse_state);
            tokadd((char)c, parse_state);
            for (i=0; i<2; i++) {
                c = nextc();
                if (c == -1) goto eof;
                if (c < '0' || '7' < c) {
                    pushback(c, parse_state);
                    break;
                }
                tokadd((char)c, parse_state);
            }
        }
        return 0;

      case 'x': /* hex constant */
        {
            int numlen;

            tokadd('\\', parse_state);
            tokadd((char)c, parse_state);
            scan_hex(parse_state->lex_p, 2, &numlen);
            if (numlen == 0) {
                yyerror("Invalid escape character syntax");
                return -1;
            }
            while (numlen--)
                tokadd((char)nextc(), parse_state);
        }
        return 0;

      case 'M':
        if ((c = nextc()) != '-') {
            yyerror("Invalid escape character syntax");
            pushback(c, parse_state);
            return 0;
        }
        tokadd('\\',parse_state); 
        tokadd('M', parse_state); 
        tokadd('-', parse_state);
        goto escaped;

      case 'C':
        if ((c = nextc()) != '-') {
            yyerror("Invalid escape character syntax");
            pushback(c, parse_state);
            return 0;
        }
        tokadd('\\', parse_state); 
        tokadd('C', parse_state); 
        tokadd('-', parse_state);
        goto escaped;

      case 'c':
        tokadd('\\', parse_state); 
        tokadd('c', parse_state);
      escaped:
        if ((c = nextc()) == '\\') {
            return tokadd_escape(term, parse_state);
        }
        else if (c == -1) goto eof;
        tokadd((char)c, parse_state);
        return 0;

      eof:
      case -1:
        yyerror("Invalid escape character syntax");
        return -1;

      default:
        if (c != '\\' || c != term)
            tokadd('\\', parse_state);
        tokadd((char)c, parse_state);
    }
    return 0;
}

static int
regx_options(rb_parse_state *parse_state)
{
    char kcode = 0;
    int options = 0;
    int c;

    newtok(parse_state);
    while (c = nextc(), ISALPHA(c)) {
        switch (c) {
          case 'i':
            options |= RE_OPTION_IGNORECASE;
            break;
          case 'x':
            options |= RE_OPTION_EXTENDED;
            break;
          case 'm':
            options |= RE_OPTION_MULTILINE;
            break;
          case 'o':
            options |= RE_OPTION_ONCE;
            break;
          case 'n':
            kcode = 16;
            break;
          case 'e':
            kcode = 32;
            break;
          case 's':
            kcode = 48;
            break;
          case 'u':
            kcode = 64;
            break;
          default:
            tokadd((char)c, parse_state);
            break;
        }
    }
    pushback(c, parse_state);
    if (toklen()) {
        tokfix();
        rb_compile_error("unknown regexp option%s - %s",
                         toklen() > 1 ? "s" : "", tok());
    }
    return options | kcode;
}

#define STR_FUNC_ESCAPE 0x01
#define STR_FUNC_EXPAND 0x02
#define STR_FUNC_REGEXP 0x04
#define STR_FUNC_QWORDS 0x08
#define STR_FUNC_SYMBOL 0x10
#define STR_FUNC_INDENT 0x20

enum string_type {
    str_squote = (0),
    str_dquote = (STR_FUNC_EXPAND),
    str_xquote = (STR_FUNC_EXPAND),
    str_regexp = (STR_FUNC_REGEXP|STR_FUNC_ESCAPE|STR_FUNC_EXPAND),
    str_sword  = (STR_FUNC_QWORDS),
    str_dword  = (STR_FUNC_QWORDS|STR_FUNC_EXPAND),
    str_ssym   = (STR_FUNC_SYMBOL),
    str_dsym   = (STR_FUNC_SYMBOL|STR_FUNC_EXPAND),
};

static int tokadd_string(int func, int term, int paren, int *nest, rb_parse_state *parse_state)
{
    int c;

    while ((c = nextc()) != -1) {
        if (paren && c == paren) {
            ++*nest;
        }
        else if (c == term) {
            if (!nest || !*nest) {
                pushback(c, parse_state);
                break;
            }
            --*nest;
        }
        else if ((func & STR_FUNC_EXPAND) && c == '#' && parse_state->lex_p < parse_state->lex_pend) {
            int c2 = *(parse_state->lex_p);
            if (c2 == '$' || c2 == '@' || c2 == '{') {
                pushback(c, parse_state);
                break;
            }
        }
        else if (c == '\\') {
            c = nextc();
            switch (c) {
              case '\n':
                if (func & STR_FUNC_QWORDS) break;
                if (func & STR_FUNC_EXPAND) continue;
                tokadd('\\', parse_state);
                break;

              case '\\':
                if (func & STR_FUNC_ESCAPE) tokadd((char)c, parse_state);
                break;

              default:
                if (func & STR_FUNC_REGEXP) {
                    pushback(c, parse_state);
                    if (tokadd_escape(term, parse_state) < 0)
                        return -1;
                    continue;
                }
                else if (func & STR_FUNC_EXPAND) {
                    pushback(c, parse_state);
                    if (func & STR_FUNC_ESCAPE) tokadd('\\', parse_state);
                    c = read_escape(parse_state);
                }
                else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
                    /* ignore backslashed spaces in %w */
                }
                else if (c != term && !(paren && c == paren)) {
                    tokadd('\\', parse_state);
                }
            }
        }
        else if (ismbchar(c)) {
            int i, len = mbclen(c)-1;

            for (i = 0; i < len; i++) {
                tokadd((char)c, parse_state);
                c = nextc();
            }
        }
        else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
            pushback(c, parse_state);
            break;
        }
        if (!c && (func & STR_FUNC_SYMBOL)) {
            func &= ~STR_FUNC_SYMBOL;
            rb_compile_error("symbol cannot contain '\\0'");
            continue;
        }
        tokadd((char)c, parse_state);
    }
    return c;
}

#define NEW_STRTERM(func, term, paren) \
  syd_node_newnode(parse_state, NODE_STRTERM, (OBJECT)(func), (OBJECT)((term) | ((paren) << (CHAR_BIT * 2))), NULL)
#define pslval ((YYSTYPE *)parse_state->lval)
static int
parse_string(quote, parse_state)
    NODE *quote;
    rb_parse_state *parse_state;
{
    int func = quote->nd_func;
    int term = nd_term(quote);
    int paren = nd_paren(quote);
    int c, space = 0;

    if (func == -1) return tSTRING_END;
    c = nextc();
    if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
        do {c = nextc();} while (ISSPACE(c));
        space = 1;
    }
    if (c == term && !quote->nd_nest) {
        if (func & STR_FUNC_QWORDS) {
            quote->nd_func = -1;
            return ' ';
        }
        if (!(func & STR_FUNC_REGEXP)) return tSTRING_END;
        pslval->num = regx_options(parse_state);
        return tREGEXP_END;
    }
    if (space) {
        pushback(c, parse_state);
        return ' ';
    }
    newtok(parse_state);
    if ((func & STR_FUNC_EXPAND) && c == '#') {
        switch (c = nextc()) {
          case '$':
          case '@':
            pushback(c, parse_state);
            return tSTRING_DVAR;
          case '{':
            return tSTRING_DBEG;
        }
        tokadd('#', parse_state);
    }
    pushback(c, parse_state);
    if (tokadd_string(func, term, paren, (int *)&quote->nd_nest, parse_state) == -1) {
        ruby_sourceline = nd_line(quote);
        rb_compile_error("unterminated string meets end of file");
        return tSTRING_END;
    }

    tokfix();
    pslval->node = NEW_STR(string_new(tok(), toklen()));
    return tSTRING_CONTENT;
}

/* Called when the lexer detects a heredoc is beginning. This pulls
   in more characters and detects what kind of heredoc it is. */
static int
heredoc_identifier(rb_parse_state *parse_state)
{
    int c = nextc(), term, func = 0;
    size_t len;

    if (c == '-') {
        c = nextc();
        func = STR_FUNC_INDENT;
    }
    switch (c) {
      case '\'':
        func |= str_squote; goto quoted;
      case '"':
        func |= str_dquote; goto quoted;
      case '`':
        func |= str_xquote;
      quoted:
        /* The heredoc indent is quoted, so its easy to find, we just
           continue to consume characters into the token buffer until
           we hit the terminating character. */
        
        newtok(parse_state);
        tokadd((char)func, parse_state);
        term = c;
        
        /* Where of where has the term gone.. */
        while ((c = nextc()) != -1 && c != term) {
            len = mbclen(c);
            do {
              tokadd((char)c, parse_state);
            } while (--len > 0 && (c = nextc()) != -1);
        }
        /* Ack! end of file or end of string. */
        if (c == -1) {
            rb_compile_error("unterminated here document identifier");
            return 0;
        }

        break;

      default:
        /* Ok, this is an unquoted heredoc ident. We just consume
           until we hit a non-ident character. */
           
        /* Do a quick check that first character is actually valid.
           if it's not, then this isn't actually a heredoc at all!
           It sucks that it's way down here in this function that in
           finally bails with this not being a heredoc.*/
           
        if (!is_identchar(c)) {
            pushback(c, parse_state);
            if (func & STR_FUNC_INDENT) {
                pushback('-', parse_state);
            }
            return 0;
        }
        
        /* Finally, setup the token buffer and begin to fill it. */
        newtok(parse_state);
        term = '"';
        tokadd((char)(func |= str_dquote), parse_state);
        do {
            len = mbclen(c);
            do { tokadd((char)c, parse_state); } while (--len > 0 && (c = nextc()) != -1);
        } while ((c = nextc()) != -1 && is_identchar(c));
        pushback(c, parse_state);
        break;
    }
    

    /* Fixup the token buffer, ie set the last character to null. */
    tokfix();
    len = parse_state->lex_p - parse_state->lex_pbeg;
    parse_state->lex_p = parse_state->lex_pend;
    pslval->id = 0;
    
    /* Tell the lexer that we're inside a string now. nd_lit is
       the heredoc identifier that we watch the stream for to 
       detect the end of the heredoc. */
    bstring str = bstrcpy(parse_state->lex_lastline);
    lex_strterm = syd_node_newnode(parse_state, NODE_HEREDOC,
                                  (OBJECT)string_new(tok(), toklen()),  /* nd_lit */
				   (OBJECT)len,                          /* nd_nth */
				   (OBJECT)str);    /* nd_orig */
    return term == '`' ? tXSTRING_BEG : tSTRING_BEG;
}

static void
heredoc_restore(here, parse_state)
    NODE *here;
    rb_parse_state *parse_state;
{
    bstring line = here->nd_orig;

    bdestroy(parse_state->lex_lastline);

    parse_state->lex_lastline = line;
    parse_state->lex_pbeg = bdata(line);
    parse_state->lex_pend = parse_state->lex_pbeg + blength(line);
    parse_state->lex_p = parse_state->lex_pbeg + here->nd_nth;
    heredoc_end = ruby_sourceline;
    ruby_sourceline = nd_line(here);
    bdestroy((bstring)here->nd_lit);
}

static int
whole_match_p(eos, len, indent, parse_state)
    char *eos;
    int len, indent;
    rb_parse_state *parse_state;
{
    char *p = parse_state->lex_pbeg;
    int n;

    if (indent) {
        while (*p && ISSPACE(*p)) p++;
    }
    n = parse_state->lex_pend - (p + len);
    if (n < 0 || (n > 0 && p[len] != '\n' && p[len] != '\r')) return FALSE;
    if (strncmp(eos, p, len) == 0) return TRUE;
    return FALSE;
}

/* Called when the lexer knows it's inside a heredoc. This function
   is responsible for detecting an expandions (ie #{}) in the heredoc
   and emitting a lex token and also detecting the end of the heredoc. */
   
static int
here_document(here, parse_state)
    NODE *here;
    rb_parse_state *parse_state;
{
    int c, func, indent = 0;
    char *eos, *p, *pend;
    long len;
    bstring str = NULL;

    /* eos == the heredoc ident that we found when the heredoc started */
    eos = bdata(here->nd_str);
    len = blength(here->nd_str) - 1;
    
    /* indicates if we should search for expansions. */
    indent = (func = *eos++) & STR_FUNC_INDENT;

    /* Ack! EOF or end of input string! */
    if ((c = nextc()) == -1) {
      error:
        rb_compile_error("can't find string \"%s\" anywhere before EOF", eos);
        heredoc_restore(lex_strterm, parse_state);
        lex_strterm = 0;
        return 0;
    }
    /* Gr. not yet sure what was_bol() means other than it seems like
       it means only 1 character has been consumed. */

    if (was_bol() && whole_match_p(eos, len, indent, parse_state)) {
        heredoc_restore(lex_strterm, parse_state);
        return tSTRING_END;
    }

    /* If aren't doing expansions, we can just scan until
       we find the identifier. */
       
    if ((func & STR_FUNC_EXPAND) == 0) {
        do {
            p = bdata(parse_state->lex_lastline);
            pend = parse_state->lex_pend;
            if (pend > p) {
                switch (pend[-1]) {
                  case '\n':
                    if (--pend == p || pend[-1] != '\r') {
                        pend++;
                        break;
                    }
                  case '\r':
                    --pend;
                }
            }
            if (str) {
                bcatblk(str, p, pend - p);
            } else {
                str = blk2bstr(p, pend - p);
            }
            if (pend < parse_state->lex_pend) bcatblk(str, "\n", 1);
            parse_state->lex_p = parse_state->lex_pend;
            if (nextc() == -1) {
                if (str) bdestroy(str);
                goto error;
            }
        } while (!whole_match_p(eos, len, indent, parse_state));
    }
    else {
        newtok(parse_state);
        if (c == '#') {
            switch (c = nextc()) {
              case '$':
              case '@':
                pushback(c, parse_state);
                return tSTRING_DVAR;
              case '{':
                return tSTRING_DBEG;
            }
            tokadd('#', parse_state);
        }
        
        /* Loop while we haven't found a the heredoc ident. */
        do {
            pushback(c, parse_state);
            /* Scan up until a \n and fill in the token buffer. */
            if ((c = tokadd_string(func, '\n', 0, NULL, parse_state)) == -1) goto error;
            
            /* We finished scanning, but didn't find a \n, so we setup the node
               and have the lexer file in more. */
            if (c != '\n') {
                pslval->node = NEW_STR(string_new(tok(), toklen()));
                return tSTRING_CONTENT;
            }
            
            /* I think this consumes the \n */
            tokadd((char)nextc(), parse_state);
            if ((c = nextc()) == -1) goto error;
        } while (!whole_match_p(eos, len, indent, parse_state));
        str = string_new(tok(), toklen());
    }
    heredoc_restore(lex_strterm, parse_state);
    lex_strterm = NEW_STRTERM(-1, 0, 0);
    pslval->node = NEW_STR(str);
    return tSTRING_CONTENT;
}

#include "shotgun/lib/grammar_lex.c.tab"

static void
arg_ambiguous()
{
    rb_warning("ambiguous first argument; put parentheses or even spaces");
}

#define IS_ARG() (parse_state->lex_state == EXPR_ARG || parse_state->lex_state == EXPR_CMDARG)

static int
yylex(YYSTYPE *yylval, void *vstate)
{
    register int c;
    int space_seen = 0;
    int cmd_state, comment_column;
    struct rb_parse_state *parse_state;
    bstring cur_line;
    parse_state = (struct rb_parse_state*)vstate;

    parse_state->lval = (void *)yylval;

    /*
    c = nextc();
    printf("lex char: %c\n", c);
    pushback(c, parse_state);
    */

    if (lex_strterm) {
        int token;
        if (nd_type(lex_strterm) == NODE_HEREDOC) {
            token = here_document(lex_strterm, parse_state);
            if (token == tSTRING_END) {
                lex_strterm = 0;
                parse_state->lex_state = EXPR_END;
            }
        }
        else {
            token = parse_string(lex_strterm, parse_state);
            if (token == tSTRING_END || token == tREGEXP_END) {
                lex_strterm = 0;
                parse_state->lex_state = EXPR_END;
            }
        }
        return token;
    }
    cmd_state = command_start;
    command_start = FALSE;
  retry:
    switch (c = nextc()) {
      case '\0':                /* NUL */
      case '\004':              /* ^D */
      case '\032':              /* ^Z */
      case -1:                  /* end of script. */
        return 0;

        /* white spaces */
      case ' ': case '\t': case '\f': case '\r':
      case '\13': /* '\v' */
        space_seen++;
        goto retry;

      case '#':         /* it's a comment */
        if(parse_state->comments) {
            comment_column = parse_state->column;
            cur_line = bfromcstralloc(50, "");
            
            while((c = nextc()) != '\n' && c != -1) {
              bconchar(cur_line, c);
            }
            
            // FIXME: used to have the file and column too, but took it out.
            ptr_array_append(parse_state->comments, cur_line);

            if(c == -1) {
                return 0;
            }
        } else {
            while ((c = nextc()) != '\n') {
                if (c == -1)
                    return 0;
            }
        }
        /* fall through */
      case '\n':
        switch (parse_state->lex_state) {
          case EXPR_BEG:
          case EXPR_FNAME:
          case EXPR_DOT:
          case EXPR_CLASS:
            goto retry;
          default:
            break;
        }
        command_start = TRUE;
        parse_state->lex_state = EXPR_BEG;
        return '\n';

      case '*':
        if ((c = nextc()) == '*') {
            if ((c = nextc()) == '=') {
                pslval->id = tPOW;
                parse_state->lex_state = EXPR_BEG;
                return tOP_ASGN;
            }
            pushback(c, parse_state);
            c = tPOW;
        }
        else {
            if (c == '=') {
                pslval->id = '*';
                parse_state->lex_state = EXPR_BEG;
                return tOP_ASGN;
            }
            pushback(c, parse_state);
            if (IS_ARG() && space_seen && !ISSPACE(c)){
                rb_warning("`*' interpreted as argument prefix");
                c = tSTAR;
            }
            else if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID) {
                c = tSTAR;
            }
            else {
                c = '*';
            }
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        return c;

      case '!':
        parse_state->lex_state = EXPR_BEG;
        if ((c = nextc()) == '=') {
            return tNEQ;
        }
        if (c == '~') {
            return tNMATCH;
        }
        pushback(c, parse_state);
        return '!';

      case '=':
        if (was_bol()) {
            /* skip embedded rd document */
            if (strncmp(parse_state->lex_p, "begin", 5) == 0 && ISSPACE(parse_state->lex_p[5])) {
                for (;;) {
                    parse_state->lex_p = parse_state->lex_pend;
                    c = nextc();
                    if (c == -1) {
                        rb_compile_error("embedded document meets end of file");
                        return 0;
                    }
                    if (c != '=') continue;
                    if (strncmp(parse_state->lex_p, "end", 3) == 0 &&
                        (parse_state->lex_p + 3 == parse_state->lex_pend || ISSPACE(parse_state->lex_p[3]))) {
                        break;
                    }
                }
                parse_state->lex_p = parse_state->lex_pend;
                goto retry;
            }
        }

        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        if ((c = nextc()) == '=') {
            if ((c = nextc()) == '=') {
                return tEQQ;
            }
            pushback(c, parse_state);
            return tEQ;
        }
        if (c == '~') {
            return tMATCH;
        }
        else if (c == '>') {
            return tASSOC;
        }
        pushback(c, parse_state);
        return '=';

      case '<':
        c = nextc();
        if (c == '<' &&
            parse_state->lex_state != EXPR_END &&
            parse_state->lex_state != EXPR_DOT &&
            parse_state->lex_state != EXPR_ENDARG && 
            parse_state->lex_state != EXPR_CLASS &&
            (!IS_ARG() || space_seen)) {
            int token = heredoc_identifier(parse_state);
            if (token) return token;
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        if (c == '=') {
            if ((c = nextc()) == '>') {
                return tCMP;
            }
            pushback(c, parse_state);
            return tLEQ;
        }
        if (c == '<') {
            if ((c = nextc()) == '=') {
                pslval->id = tLSHFT;
                parse_state->lex_state = EXPR_BEG;
                return tOP_ASGN;
            }
            pushback(c, parse_state);
            return tLSHFT;
        }
        pushback(c, parse_state);
        return '<';

      case '>':
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        if ((c = nextc()) == '=') {
            return tGEQ;
        }
        if (c == '>') {
            if ((c = nextc()) == '=') {
                pslval->id = tRSHFT;
                parse_state->lex_state = EXPR_BEG;
                return tOP_ASGN;
            }
            pushback(c, parse_state);
            return tRSHFT;
        }
        pushback(c, parse_state);
        return '>';

      case '"':
        lex_strterm = NEW_STRTERM(str_dquote, '"', 0);
        return tSTRING_BEG;

      case '`':
        if (parse_state->lex_state == EXPR_FNAME) {
            parse_state->lex_state = EXPR_END;
            return c;
        }
        if (parse_state->lex_state == EXPR_DOT) {
            if (cmd_state)
                parse_state->lex_state = EXPR_CMDARG;
            else
                parse_state->lex_state = EXPR_ARG;
            return c;
        }
        lex_strterm = NEW_STRTERM(str_xquote, '`', 0);
        pslval->id = 0; /* so that xstring gets used normally */
        return tXSTRING_BEG;

      case '\'':
        lex_strterm = NEW_STRTERM(str_squote, '\'', 0);
        pslval->id = 0; /* so that xstring gets used normally */
        return tSTRING_BEG;

      case '?':
        if (parse_state->lex_state == EXPR_END || parse_state->lex_state == EXPR_ENDARG) {
            parse_state->lex_state = EXPR_BEG;
            return '?';
        }
        c = nextc();
        if (c == -1) {
            rb_compile_error("incomplete character syntax");
            return 0;
        }
        if (ISSPACE(c)){
            if (!IS_ARG()){
                int c2 = 0;
                switch (c) {
                  case ' ':
                    c2 = 's';
                    break;
                  case '\n':
                    c2 = 'n';
                    break;
                  case '\t':
                    c2 = 't';
                    break;
                  case '\v':
                    c2 = 'v';
                    break;
                  case '\r':
                    c2 = 'r';
                    break;
                  case '\f':
                    c2 = 'f';
                    break;
                }
                if (c2) {
                    rb_warn("invalid character syntax; use ?\\%c", c2);
                }
            }
          ternary:
            pushback(c, parse_state);
            parse_state->lex_state = EXPR_BEG;
            parse_state->ternary_colon = 1;
            return '?';
        }
        else if (ismbchar(c)) {
            rb_warn("multibyte character literal not supported yet; use ?\\%.3o", c);
            goto ternary;
        }
        else if ((ISALNUM(c) || c == '_') && parse_state->lex_p < parse_state->lex_pend && is_identchar(*(parse_state->lex_p))) {
            goto ternary;
        }
        else if (c == '\\') {
            c = read_escape(parse_state);
        }
        c &= 0xff;
        parse_state->lex_state = EXPR_END;
        pslval->node = NEW_FIXNUM((intptr_t)c);
        return tINTEGER;

      case '&':
        if ((c = nextc()) == '&') {
            parse_state->lex_state = EXPR_BEG;
            if ((c = nextc()) == '=') {
                pslval->id = tANDOP;
                parse_state->lex_state = EXPR_BEG;
                return tOP_ASGN;
            }
            pushback(c, parse_state);
            return tANDOP;
        }
        else if (c == '=') {
            pslval->id = '&';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        pushback(c, parse_state);
        if (IS_ARG() && space_seen && !ISSPACE(c)){
            rb_warning("`&' interpreted as argument prefix");
            c = tAMPER;
        }
        else if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID) {
            c = tAMPER;
        }
        else {
            c = '&';
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG;
        }
        return c;

      case '|':
        if ((c = nextc()) == '|') {
            parse_state->lex_state = EXPR_BEG;
            if ((c = nextc()) == '=') {
                pslval->id = tOROP;
                parse_state->lex_state = EXPR_BEG;
                return tOP_ASGN;
            }
            pushback(c, parse_state);
            return tOROP;
        }
        if (c == '=') {
            pslval->id = '|';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        if (parse_state->lex_state == EXPR_FNAME || parse_state->lex_state == EXPR_DOT) {
            parse_state->lex_state = EXPR_ARG;
        }
        else {
            parse_state->lex_state = EXPR_BEG;
        }
        pushback(c, parse_state);
        return '|';

      case '+':
        c = nextc();
        if (parse_state->lex_state == EXPR_FNAME || parse_state->lex_state == EXPR_DOT) {
            parse_state->lex_state = EXPR_ARG;
            if (c == '@') {
                return tUPLUS;
            }
            pushback(c, parse_state);
            return '+';
        }
        if (c == '=') {
            pslval->id = '+';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID ||
            (IS_ARG() && space_seen && !ISSPACE(c))) {
            if (IS_ARG()) arg_ambiguous();
            parse_state->lex_state = EXPR_BEG;
            pushback(c, parse_state);
            if (ISDIGIT(c)) {
                c = '+';
                goto start_num;
            }
            return tUPLUS;
        }
        parse_state->lex_state = EXPR_BEG;
        pushback(c, parse_state);
        return '+';

      case '-':
        c = nextc();
        if (parse_state->lex_state == EXPR_FNAME || parse_state->lex_state == EXPR_DOT) {
            parse_state->lex_state = EXPR_ARG;
            if (c == '@') {
                return tUMINUS;
            }
            pushback(c, parse_state);
            return '-';
        }
        if (c == '=') {
            pslval->id = '-';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID ||
            (IS_ARG() && space_seen && !ISSPACE(c))) {
            if (IS_ARG()) arg_ambiguous();
            parse_state->lex_state = EXPR_BEG;
            pushback(c, parse_state);
            if (ISDIGIT(c)) {
                return tUMINUS_NUM;
            }
            return tUMINUS;
        }
        parse_state->lex_state = EXPR_BEG;
        pushback(c, parse_state);
        return '-';

      case '.':
        parse_state->lex_state = EXPR_BEG;
        if ((c = nextc()) == '.') {
            if ((c = nextc()) == '.') {
                return tDOT3;
            }
            pushback(c, parse_state);
            return tDOT2;
        }
        pushback(c, parse_state);
        if (ISDIGIT(c)) {
            yyerror("no .<digit> floating literal anymore; put 0 before dot");
        }
        parse_state->lex_state = EXPR_DOT;
        return '.';

      start_num:
      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
        {
            int is_float, seen_point, seen_e, nondigit;

            is_float = seen_point = seen_e = nondigit = 0;
            parse_state->lex_state = EXPR_END;
            newtok(parse_state);
            if (c == '-' || c == '+') {
                tokadd((char)c,parse_state);
                c = nextc();
            }
            if (c == '0') {
                int start = toklen();
                c = nextc();
                if (c == 'x' || c == 'X') {
                    /* hexadecimal */
                    c = nextc();
                    if (ISXDIGIT(c)) {
                        do {
                            if (c == '_') {
                                if (nondigit) break;
                                nondigit = c;
                                continue;
                            }
                            if (!ISXDIGIT(c)) break;
                            nondigit = 0;
                            tokadd((char)c,parse_state);
                        } while ((c = nextc()) != -1);
                    }
                    pushback(c, parse_state);
                    tokfix();
                    if (toklen() == start) {
                        yyerror("numeric literal without digits");
                    }
                    else if (nondigit) goto trailing_uc;
                    pslval->node = NEW_HEXNUM(string_new2(tok()));
                    return tINTEGER;
                }
                if (c == 'b' || c == 'B') {
                    /* binary */
                    c = nextc();
                    if (c == '0' || c == '1') {
                        do {
                            if (c == '_') {
                                if (nondigit) break;
                                nondigit = c;
                                continue;
                            }
                            if (c != '0' && c != '1') break;
                            nondigit = 0;
                            tokadd((char)c, parse_state);
                        } while ((c = nextc()) != -1);
                    }
                    pushback(c, parse_state);
                    tokfix();
                    if (toklen() == start) {
                        yyerror("numeric literal without digits");
                    }
                    else if (nondigit) goto trailing_uc;
                    pslval->node = NEW_BINNUM(string_new2(tok()));
                    return tINTEGER;
                }
                if (c == 'd' || c == 'D') {
                    /* decimal */
                    c = nextc();
                    if (ISDIGIT(c)) {
                        do {
                            if (c == '_') {
                                if (nondigit) break;
                                nondigit = c;
                                continue;
                            }
                            if (!ISDIGIT(c)) break;
                            nondigit = 0;
                            tokadd((char)c, parse_state);
                        } while ((c = nextc()) != -1);
                    }
                    pushback(c, parse_state);
                    tokfix();
                    if (toklen() == start) {
                        yyerror("numeric literal without digits");
                    }
                    else if (nondigit) goto trailing_uc;
                    pslval->node = NEW_NUMBER(string_new2(tok()));
                    return tINTEGER;
                }
                if (c == '_') {
                    /* 0_0 */
                    goto octal_number;
                }
                if (c == 'o' || c == 'O') {
                    /* prefixed octal */
                    c = nextc();
                    if (c == '_') {
                        yyerror("numeric literal without digits");
                    }
                }
                if (c >= '0' && c <= '7') {
                    /* octal */
                  octal_number:
                    do {
                        if (c == '_') {
                            if (nondigit) break;
                            nondigit = c;
                            continue;
                        }
                        if (c < '0' || c > '7') break;
                        nondigit = 0;
                        tokadd((char)c, parse_state);
                    } while ((c = nextc()) != -1);
                    if (toklen() > start) {
                        pushback(c, parse_state);
                        tokfix();
                        if (nondigit) goto trailing_uc;
                        pslval->node = NEW_OCTNUM(string_new2(tok()));
                        return tINTEGER;
                    }
                    if (nondigit) {
                        pushback(c, parse_state);
                        goto trailing_uc;
                    }
                }
                if (c > '7' && c <= '9') {
                    yyerror("Illegal octal digit");
                }
                else if (c == '.' || c == 'e' || c == 'E') {
                    tokadd('0', parse_state);
                }
                else {
                    pushback(c, parse_state);
                    pslval->node = NEW_FIXNUM(0);
                    return tINTEGER;
                }
            }

            for (;;) {
                switch (c) {
                  case '0': case '1': case '2': case '3': case '4':
                  case '5': case '6': case '7': case '8': case '9':
                    nondigit = 0;
                    tokadd((char)c, parse_state);
                    break;

                  case '.':
                    if (nondigit) goto trailing_uc;
                    if (seen_point || seen_e) {
                        goto decode_num;
                    }
                    else {
                        int c0 = nextc();
                        if (!ISDIGIT(c0)) {
                            pushback(c0, parse_state);
                            goto decode_num;
                        }
                        c = c0;
                    }
                    tokadd('.', parse_state);
                    tokadd((char)c, parse_state);
                    is_float++;
                    seen_point++;
                    nondigit = 0;
                    break;

                  case 'e':
                  case 'E':
                    if (nondigit) {
                        pushback(c, parse_state);
                        c = nondigit;
                        goto decode_num;
                    }
                    if (seen_e) {
                        goto decode_num;
                    }
                    tokadd((char)c, parse_state);
                    seen_e++;
                    is_float++;
                    nondigit = c;
                    c = nextc();
                    if (c != '-' && c != '+') continue;
                    tokadd((char)c, parse_state);
                    nondigit = c;
                    break;

                  case '_':     /* `_' in number just ignored */
                    if (nondigit) goto decode_num;
                    nondigit = c;
                    break;

                  default:
                    goto decode_num;
                }
                c = nextc();
            }

          decode_num:
            pushback(c, parse_state);
            tokfix();
            if (nondigit) {
                char tmp[30];
              trailing_uc:
                snprintf(tmp, sizeof(tmp), "trailing `%c' in number", nondigit);
                yyerror(tmp);
            }
            if (is_float) {
                /* Some implementations of strtod() don't guarantee to
                 * set errno, so we need to reset it ourselves.
                 */
                errno = 0;

                strtod(tok(), 0);
                if (errno == ERANGE) {
                    rb_warn("Float %s out of range", tok());
                    errno = 0;
                }
                pslval->node = NEW_FLOAT(string_new2(tok()));
                return tFLOAT;
            }
            pslval->node = NEW_NUMBER(string_new2(tok()));
            return tINTEGER;
        }

      case ']':
      case '}':
      case ')':
        COND_LEXPOP();
        CMDARG_LEXPOP();
        parse_state->lex_state = EXPR_END;
        return c;

      case ':':
        c = nextc();
        if (c == ':') {
            if (parse_state->lex_state == EXPR_BEG ||  parse_state->lex_state == EXPR_MID ||
                parse_state->lex_state == EXPR_CLASS || (IS_ARG() && space_seen)) {
                parse_state->lex_state = EXPR_BEG;
                return tCOLON3;
            }
            parse_state->lex_state = EXPR_DOT;
            return tCOLON2;
        }
        if (parse_state->lex_state == EXPR_END || parse_state->lex_state == EXPR_ENDARG || ISSPACE(c)) {
            pushback(c, parse_state);
            parse_state->lex_state = EXPR_BEG;
            return ':';
        }
        switch (c) {
          case '\'':
            lex_strterm = NEW_STRTERM(str_ssym, (intptr_t)c, 0);
            break;
          case '"':
            lex_strterm = NEW_STRTERM(str_dsym, (intptr_t)c, 0);
            break;
          default:
            pushback(c, parse_state);
            break;
        }
        parse_state->lex_state = EXPR_FNAME;
        return tSYMBEG;

      case '/':
        if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID) {
            lex_strterm = NEW_STRTERM(str_regexp, '/', 0);
            return tREGEXP_BEG;
        }
        if ((c = nextc()) == '=') {
            pslval->id = '/';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        pushback(c, parse_state);
        if (IS_ARG() && space_seen) {
            if (!ISSPACE(c)) {
                arg_ambiguous();
                lex_strterm = NEW_STRTERM(str_regexp, '/', 0);
                return tREGEXP_BEG;
            }
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        return '/';

      case '^':
        if ((c = nextc()) == '=') {
            pslval->id = '^';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        pushback(c, parse_state);
        return '^';

      case ';':
        command_start = TRUE;
      case ',':
        parse_state->lex_state = EXPR_BEG;
        return c;

      case '~':
        if (parse_state->lex_state == EXPR_FNAME || parse_state->lex_state == EXPR_DOT) {
            if ((c = nextc()) != '@') {
                pushback(c, parse_state);
            }
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        return '~';

      case '(':
        command_start = TRUE;
        if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID) {
            c = tLPAREN;
        }
        else if (space_seen) {
            if (parse_state->lex_state == EXPR_CMDARG) {
                c = tLPAREN_ARG;
            }
            else if (parse_state->lex_state == EXPR_ARG) {
                rb_warn("don't put space before argument parentheses");
                c = '(';
            }
        }
        COND_PUSH(0);
        CMDARG_PUSH(0);
        parse_state->lex_state = EXPR_BEG;
        return c;

      case '[':
        if (parse_state->lex_state == EXPR_FNAME || parse_state->lex_state == EXPR_DOT) {
            parse_state->lex_state = EXPR_ARG;
            if ((c = nextc()) == ']') {
                if ((c = nextc()) == '=') {
                    return tASET;
                }
                pushback(c, parse_state);
                return tAREF;
            }
            pushback(c, parse_state);
            return '[';
        }
        else if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID) {
            c = tLBRACK;
        }
        else if (IS_ARG() && space_seen) {
            c = tLBRACK;
        }
        parse_state->lex_state = EXPR_BEG;
        COND_PUSH(0);
        CMDARG_PUSH(0);
        return c;

      case '{':
        if (IS_ARG() || parse_state->lex_state == EXPR_END)
            c = '{';          /* block (primary) */
        else if (parse_state->lex_state == EXPR_ENDARG)
            c = tLBRACE_ARG;  /* block (expr) */
        else
            c = tLBRACE;      /* hash */
        COND_PUSH(0);
        CMDARG_PUSH(0);
        parse_state->lex_state = EXPR_BEG;
        return c;

      case '\\':
        c = nextc();
        if (c == '\n') {
            space_seen = 1;
            goto retry; /* skip \\n */
        }
        pushback(c, parse_state);
        if(parse_state->lex_state == EXPR_BEG 
           || parse_state->lex_state == EXPR_MID || space_seen) {
            parse_state->lex_state = EXPR_DOT;
            return tUBS;
        }
        parse_state->lex_state = EXPR_DOT;
        return '\\';

      case '%':
        if (parse_state->lex_state == EXPR_BEG || parse_state->lex_state == EXPR_MID) {
            intptr_t term;
            intptr_t paren;
            char tmpstr[256];
            char *cur;

            c = nextc();
          quotation:
            if (!ISALNUM(c)) {
                term = c;
                c = 'Q';
            }
            else {
                term = nextc();
                if (ISALNUM(term) || ismbchar(term)) {
                    cur = tmpstr;
                    *cur++ = c;
                    while(ISALNUM(term) || ismbchar(term)) {
                        *cur++ = term;
                        term = nextc();
                    }
                    *cur = 0;
                    c = 1;
                    
                }
            }
            if (c == -1 || term == -1) {
                rb_compile_error("unterminated quoted string meets end of file");
                return 0;
            }
            paren = term;
            if (term == '(') term = ')';
            else if (term == '[') term = ']';
            else if (term == '{') term = '}';
            else if (term == '<') term = '>';
            else paren = 0;

            switch (c) {
              case 'Q':
                lex_strterm = NEW_STRTERM(str_dquote, term, paren);
                return tSTRING_BEG;

              case 'q':
                lex_strterm = NEW_STRTERM(str_squote, term, paren);
                return tSTRING_BEG;

              case 'W':
                lex_strterm = NEW_STRTERM(str_dquote | STR_FUNC_QWORDS, term, paren);
                do {c = nextc();} while (ISSPACE(c));
                pushback(c, parse_state);
                return tWORDS_BEG;

              case 'w':
                lex_strterm = NEW_STRTERM(str_squote | STR_FUNC_QWORDS, term, paren);
                do {c = nextc();} while (ISSPACE(c));
                pushback(c, parse_state);
                return tQWORDS_BEG;

              case 'x':
                lex_strterm = NEW_STRTERM(str_xquote, term, paren);
                pslval->id = 0;
                return tXSTRING_BEG;

              case 'r':
                lex_strterm = NEW_STRTERM(str_regexp, term, paren);
                return tREGEXP_BEG;

              case 's':
                lex_strterm = NEW_STRTERM(str_ssym, term, paren);
                parse_state->lex_state = EXPR_FNAME;
                return tSYMBEG;

              case 1:
                lex_strterm = NEW_STRTERM(str_xquote, term, paren);
                pslval->id = rb_intern(tmpstr);
                return tXSTRING_BEG;

              default:
                lex_strterm = NEW_STRTERM(str_xquote, term, paren);
                tmpstr[0] = c;
                tmpstr[1] = 0;
                pslval->id = rb_intern(tmpstr);
                return tXSTRING_BEG;
            }
        }
        if ((c = nextc()) == '=') {
            pslval->id = '%';
            parse_state->lex_state = EXPR_BEG;
            return tOP_ASGN;
        }
        if (IS_ARG() && space_seen && !ISSPACE(c)) {
            goto quotation;
        }
        switch (parse_state->lex_state) {
          case EXPR_FNAME: case EXPR_DOT:
            parse_state->lex_state = EXPR_ARG; break;
          default:
            parse_state->lex_state = EXPR_BEG; break;
        }
        pushback(c, parse_state);
        return '%';

      case '$':
        parse_state->lex_state = EXPR_END;
        newtok(parse_state);
        c = nextc();
        switch (c) {
          case '_':             /* $_: last read line string */
            c = nextc();
            if (is_identchar(c)) {
                tokadd('$', parse_state);
                tokadd('_', parse_state);
                break;
            }
            pushback(c, parse_state);
            c = '_';
            /* fall through */
          case '~':             /* $~: match-data */
            local_cnt(c);
            /* fall through */
          case '*':             /* $*: argv */
          case '$':             /* $$: pid */
          case '?':             /* $?: last status */
          case '!':             /* $!: error string */
          case '@':             /* $@: error position */
          case '/':             /* $/: input record separator */
          case '\\':            /* $\: output record separator */
          case ';':             /* $;: field separator */
          case ',':             /* $,: output field separator */
          case '.':             /* $.: last read line number */
          case '=':             /* $=: ignorecase */
          case ':':             /* $:: load path */
          case '<':             /* $<: reading filename */
          case '>':             /* $>: default output handle */
          case '\"':            /* $": already loaded files */
            tokadd('$', parse_state);
            tokadd((char)c, parse_state);
            tokfix();
            pslval->id = rb_intern(tok());
            return tGVAR;

          case '-':
            tokadd('$', parse_state);
            tokadd((char)c, parse_state);
            c = nextc();
            tokadd((char)c, parse_state);
            tokfix();
            pslval->id = rb_intern(tok());
            /* xxx shouldn't check if valid option variable */
            return tGVAR;

          case '&':             /* $&: last match */
          case '`':             /* $`: string before last match */
          case '\'':            /* $': string after last match */
          case '+':             /* $+: string matches last paren. */
            pslval->node = NEW_BACK_REF((intptr_t)c);
            return tBACK_REF;

          case '1': case '2': case '3':
          case '4': case '5': case '6':
          case '7': case '8': case '9':
            tokadd('$', parse_state);
            do {
                tokadd((char)c, parse_state);
                c = nextc();
            } while (ISDIGIT(c));
            pushback(c, parse_state);
            tokfix();
            pslval->node = NEW_NTH_REF((intptr_t)atoi(tok()+1));
            return tNTH_REF;

          default:
            if (!is_identchar(c)) {
                pushback(c, parse_state);
                return '$';
            }
          case '0':
            tokadd('$', parse_state);
        }
        break;

      case '@':
        c = nextc();
        newtok(parse_state);
        tokadd('@', parse_state);
        if (c == '@') {
            tokadd('@', parse_state);
            c = nextc();
        }
        if (ISDIGIT(c)) {
            if (tokidx == 1) {
                rb_compile_error("`@%c' is not allowed as an instance variable name", c);
            }
            else {
                rb_compile_error("`@@%c' is not allowed as a class variable name", c);
            }
        }
        if (!is_identchar(c)) {
            pushback(c, parse_state);
            return '@';
        }
        break;

      case '_':
        if (was_bol() && whole_match_p("__END__", 7, 0, parse_state)) {
            parse_state->lex_lastline = 0;
            return -1;
        }
        newtok(parse_state);
        break;

      default:
        if (!is_identchar(c)) {
            rb_compile_error("Invalid char `\\%03o' in expression", c);
            goto retry;
        }

        newtok(parse_state);
        break;
    }

    do {
        tokadd((char)c, parse_state);
        if (ismbchar(c)) {
            int i, len = mbclen(c)-1;

            for (i = 0; i < len; i++) {
                c = nextc();
                tokadd((char)c, parse_state);
            }
        }
        c = nextc();
    } while (is_identchar(c));
    if ((c == '!' || c == '?') && is_identchar(tok()[0]) && !peek('=')) {
        tokadd((char)c, parse_state);
    }
    else {
        pushback(c, parse_state);
    }
    tokfix();

    {
        int result = 0;

        switch (tok()[0]) {
          case '$':
            parse_state->lex_state = EXPR_END;
            result = tGVAR;
            break;
          case '@':
            parse_state->lex_state = EXPR_END;
            if (tok()[1] == '@')
                result = tCVAR;
            else
                result = tIVAR;
            break;

          default:
            if (toklast() == '!' || toklast() == '?') {
                result = tFID;
            }
            else {
                if (parse_state->lex_state == EXPR_FNAME) {
                    if ((c = nextc()) == '=' && !peek('~') && !peek('>') &&
                        (!peek('=') || (parse_state->lex_p + 1 < parse_state->lex_pend && (parse_state->lex_p)[1] == '>'))) {
                        result = tIDENTIFIER;
                        tokadd((char)c, parse_state);
                        tokfix();
                    }
                    else {
                        pushback(c, parse_state);
                    }
                }
                if (result == 0 && ISUPPER(tok()[0])) {
                    result = tCONSTANT;
                }
                else {
                    result = tIDENTIFIER;
                }
            }

            if (parse_state->lex_state != EXPR_DOT) {
                const struct kwtable *kw;

                /* See if it is a reserved word.  */
                kw = syd_reserved_word(tok(), toklen());
                if (kw) {
                    enum lex_state state = parse_state->lex_state;
                    parse_state->lex_state = kw->state;
                    if (state == EXPR_FNAME) {
                        pslval->id = rb_intern(kw->name);
                    }
                    if (kw->id[0] == kDO) {
                        if (COND_P()) return kDO_COND;
                        if (CMDARG_P() && state != EXPR_CMDARG)
                            return kDO_BLOCK;
                        if (state == EXPR_ENDARG)
                            return kDO_BLOCK;
                        return kDO;
                    }
                    if (state == EXPR_BEG)
                        return kw->id[0];
                    else {
                        if (kw->id[0] != kw->id[1])
                            parse_state->lex_state = EXPR_BEG;
                        return kw->id[1];
                    }
                }
            }

            if (parse_state->lex_state == EXPR_BEG ||
                parse_state->lex_state == EXPR_MID ||
                parse_state->lex_state == EXPR_DOT ||
                parse_state->lex_state == EXPR_ARG ||
                parse_state->lex_state == EXPR_CMDARG) {
                if (cmd_state) {
                    parse_state->lex_state = EXPR_CMDARG;
                }
                else {
                    parse_state->lex_state = EXPR_ARG;
                }
            }
            else {
                parse_state->lex_state = EXPR_END;
            }
        }
        pslval->id = rb_intern(tok());

        if (is_local_id(pslval->id) && local_id(pslval->id)) {
            parse_state->lex_state = EXPR_END;
        }

        return result;
    }
}


static NODE*
syd_node_newnode(rb_parse_state *st, enum node_type type,
                 OBJECT a0, OBJECT a1, OBJECT a2)
{
    NODE *n = (NODE*)pt_allocate(st, sizeof(NODE));

    n->flags = 0;
    nd_set_type(n, type);
    nd_set_line(n, ruby_sourceline);
    n->nd_file = ruby_sourcefile;

    n->u1.value = a0;
    n->u2.value = a1;
    n->u3.value = a2;

    return n;
}

static NODE*
newline_node(parse_state, node)
    rb_parse_state *parse_state;
    NODE *node;
{
    NODE *nl = 0;
    if (node) {
        if (nd_type(node) == NODE_NEWLINE) return node;
        nl = NEW_NEWLINE(node);
        fixpos(nl, node);
        nl->nd_nth = nd_line(node);
    }
    return nl;
}

static void
fixpos(node, orig)
    NODE *node, *orig;
{
    if (!node) return;
    if (!orig) return;
    if (orig == (NODE*)1) return;
    node->nd_file = orig->nd_file;
    nd_set_line(node, nd_line(orig));
}

static void
parser_warning(rb_parse_state *parse_state, NODE *node, const char *mesg)
{
    int line = ruby_sourceline;
    if(parse_state->emit_warnings) {
      ruby_sourceline = nd_line(node);
      printf("%s:%zi: warning: %s\n", ruby_sourcefile, ruby_sourceline, mesg);
      ruby_sourceline = line;
    }
}

static NODE*
block_append(parse_state, head, tail)
    rb_parse_state *parse_state;
    NODE *head, *tail;
{
    NODE *end, *h = head;

    if (tail == 0) return head;

  again:
    if (h == 0) return tail;
    switch (nd_type(h)) {
      case NODE_NEWLINE:
        h = h->nd_next;
        goto again;
      case NODE_STR:
      case NODE_LIT:
        parser_warning(parse_state, h, "unused literal ignored");
      default:
        h = end = NEW_BLOCK(head);
        end->nd_end = end;
        fixpos(end, head);
        head = end;
        break;
      case NODE_BLOCK:
        end = h->nd_end;
        break;
    }

    if (RTEST(ruby_verbose)) {
        NODE *nd = end->nd_head;
      newline:
        switch (nd_type(nd)) {
          case NODE_RETURN:
          case NODE_BREAK:
          case NODE_NEXT:
          case NODE_REDO:
          case NODE_RETRY:
            parser_warning(parse_state, nd, "statement not reached");
            break;

        case NODE_NEWLINE:
            nd = nd->nd_next;
            goto newline;

          default:
            break;
        }
    }

    if (nd_type(tail) != NODE_BLOCK) {
        tail = NEW_BLOCK(tail);
        tail->nd_end = tail;
    }
    end->nd_next = tail;
    h->nd_end = tail->nd_end;
    return head;
}

/* append item to the list */
static NODE*
list_append(parse_state, list, item)
    rb_parse_state *parse_state;
    NODE *list, *item;
{
    NODE *last;

    if (list == 0) return NEW_LIST(item);
    if (list->nd_next) {
        last = list->nd_next->nd_end;
    }
    else {
        last = list;
    }

    list->nd_alen += 1;
    last->nd_next = NEW_LIST(item);
    list->nd_next->nd_end = last->nd_next;
    return list;
}

/* concat two lists */
static NODE*
list_concat(head, tail)
    NODE *head, *tail;
{
    NODE *last;

    if (head->nd_next) {
        last = head->nd_next->nd_end;
    }
    else {
        last = head;
    }

    head->nd_alen += tail->nd_alen;
    last->nd_next = tail;
    if (tail->nd_next) {
        head->nd_next->nd_end = tail->nd_next->nd_end;
    }
    else {
        head->nd_next->nd_end = tail;
    }

    return head;
}

/* concat two string literals */
static NODE *
literal_concat(parse_state, head, tail)
    rb_parse_state *parse_state;
    NODE *head, *tail;
{
    enum node_type htype;

    if (!head) return tail;
    if (!tail) return head;

    htype = nd_type(head);
    if (htype == NODE_EVSTR) {
        NODE *node = NEW_DSTR(string_new(0, 0));
        head = list_append(parse_state, node, head);
    }
    switch (nd_type(tail)) {
      case NODE_STR:
        if (htype == NODE_STR) {
            bconcat(head->nd_str, tail->nd_str);
			bdestroy(tail->nd_str);
        }
        else {
            list_append(parse_state, head, tail);
        }
        break;

      case NODE_DSTR:
        if (htype == NODE_STR) {
            bconcat(head->nd_str, tail->nd_str);
            bdestroy(tail->nd_str);

            tail->nd_lit = head->nd_lit;
            head = tail;
        }
        else {
            nd_set_type(tail, NODE_ARRAY);
            tail->nd_head = NEW_STR(tail->nd_lit);
            list_concat(head, tail);
        }
        break;

      case NODE_EVSTR:
        if (htype == NODE_STR) {
            nd_set_type(head, NODE_DSTR);
            head->nd_alen = 1;
        }
        list_append(parse_state, head, tail);
        break;
    }
    return head;
}

static NODE *
evstr2dstr(parse_state, node)
    rb_parse_state *parse_state;
    NODE *node;
{
    if (nd_type(node) == NODE_EVSTR) {
        node = list_append(parse_state, NEW_DSTR(string_new(0, 0)), node);
    }
    return node;
}

static NODE *
new_evstr(parse_state, node)
    rb_parse_state *parse_state;
    NODE *node;
{
    NODE *head = node;

  again:
    if (node) {
        switch (nd_type(node)) {
          case NODE_STR: case NODE_DSTR: case NODE_EVSTR:
            return node;
          case NODE_NEWLINE:
            node = node->nd_next;
            goto again;
        }
    }
    return NEW_EVSTR(head);
}

static const struct {
    ID token;
    const char name[12];
} op_tbl[] = {
    {tDOT2,     ".."},
    {tDOT3,     "..."},
    {'+',       "+"},
    {'-',       "-"},
    {'+',       "+(binary)"},
    {'-',       "-(binary)"},
    {'*',       "*"},
    {'/',       "/"},
    {'%',       "%"},
    {tPOW,      "**"},
    {tUPLUS,    "+@"},
    {tUMINUS,   "-@"},
    {tUPLUS,    "+(unary)"},
    {tUMINUS,   "-(unary)"},
    {'|',       "|"},
    {'^',       "^"},
    {'&',       "&"},
    {tCMP,      "<=>"},
    {'>',       ">"},
    {tGEQ,      ">="},
    {'<',       "<"},
    {tLEQ,      "<="},
    {tEQ,       "=="},
    {tEQQ,      "==="},
    {tNEQ,      "!="},
    {tMATCH,    "=~"},
    {tNMATCH,   "!~"},
    {'!',       "!"},
    {'~',       "~"},
    {'!',       "!(unary)"},
    {'~',       "~(unary)"},
    {'!',       "!@"},
    {'~',       "~@"},
    {tAREF,     "[]"},
    {tASET,     "[]="},
    {tLSHFT,    "<<"},
    {tRSHFT,    ">>"},
    {tCOLON2,   "::"},
    {'`',       "`"},
    {0, ""}
};

static ID convert_op(ID id) {
    int i;
    for(i = 0; op_tbl[i].token; i++) {
        if(op_tbl[i].token == id) {
            return rb_intern(op_tbl[i].name);
        }
    }
    return id;
}

static NODE *
call_op(recv, id, narg, arg1, parse_state)
    NODE *recv;
    ID id;
    int narg;
    NODE *arg1;
    rb_parse_state *parse_state;
{
    value_expr(recv);
    if (narg == 1) {
        value_expr(arg1);
        arg1 = NEW_LIST(arg1);
    }
    else {
        arg1 = 0;
    }
    
    id = convert_op(id);
    
    
    return NEW_CALL(recv, id, arg1);
}

static NODE*
match_gen(node1, node2, parse_state)
    NODE *node1;
    NODE *node2;
    rb_parse_state *parse_state;
{
    local_cnt('~');

    value_expr(node1);
    value_expr(node2);
    if (node1) {
        switch (nd_type(node1)) {
          case NODE_DREGX:
          case NODE_DREGX_ONCE:
            return NEW_MATCH2(node1, node2);

          case NODE_REGEX:
              return NEW_MATCH2(node1, node2);
        }
    }

    if (node2) {
        switch (nd_type(node2)) {
          case NODE_DREGX:
          case NODE_DREGX_ONCE:
            return NEW_MATCH3(node2, node1);

          case NODE_REGEX:
            return NEW_MATCH3(node2, node1);
        }
    }

    return NEW_CALL(node1, convert_op(tMATCH), NEW_LIST(node2));
}

static NODE*
syd_gettable(parse_state, id)
    rb_parse_state *parse_state;
    ID id;
{
    if (id == kSELF) {
        return NEW_SELF();
    }
    else if (id == kNIL) {
        return NEW_NIL();
    }
    else if (id == kTRUE) {
        return NEW_TRUE();
    }
    else if (id == kFALSE) {
        return NEW_FALSE();
    }
    else if (id == k__FILE__) {
        return NEW_FILE();
    }
    else if (id == k__LINE__) {
        return NEW_FIXNUM(ruby_sourceline);
    }
    else if (is_local_id(id)) {
        if (local_id(id)) return NEW_LVAR(id);
        /* method call without arguments */
        return NEW_VCALL(id);
    }
    else if (is_global_id(id)) {
        return NEW_GVAR(id);
    }
    else if (is_instance_id(id)) {
        return NEW_IVAR(id);
    }
    else if (is_const_id(id)) {
        return NEW_CONST(id);
    }
    else if (is_class_id(id)) {
        return NEW_CVAR(id);
    }
    /* FIXME: indicate which identifier. */
    rb_compile_error("identifier is not valid 1\n");
    return 0;
}

static void
reset_block(rb_parse_state *parse_state) {
  if(!parse_state->block_vars) {
    parse_state->block_vars = var_table_create();
  } else {
    parse_state->block_vars = var_table_push(parse_state->block_vars);
  }
}

static NODE *
extract_block_vars(rb_parse_state *parse_state, NODE* node, var_table vars)
{
    int i;
    NODE *var, *out = node;
        
    if (!node) goto out;
    if(var_table_size(vars) == 0) goto out;
        
    var = NULL;
    for(i = 0; i < var_table_size(vars); i++) {
        var = NEW_DASGN_CURR(var_table_get(vars, i), var);
    }
    out = block_append(parse_state, var, node);

out:
  assert(vars == parse_state->block_vars);
  parse_state->block_vars = var_table_pop(parse_state->block_vars);

  return out;
}

static NODE*
assignable(id, val, parse_state)
    ID id;
    NODE *val;
    rb_parse_state *parse_state;
{
    value_expr(val);
    if (id == kSELF) {
        yyerror("Can't change the value of self");
    }
    else if (id == kNIL) {
        yyerror("Can't assign to nil");
    }
    else if (id == kTRUE) {
        yyerror("Can't assign to true");
    }
    else if (id == kFALSE) {
        yyerror("Can't assign to false");
    }
    else if (id == k__FILE__) {
        yyerror("Can't assign to __FILE__");
    }
    else if (id == k__LINE__) {
        yyerror("Can't assign to __LINE__");
    }
    else if (is_local_id(id)) {
        if(parse_state->block_vars) {
          var_table_add(parse_state->block_vars, id);
        }
        return NEW_LASGN(id, val);      
    }
    else if (is_global_id(id)) {
        return NEW_GASGN(id, val);
    }
    else if (is_instance_id(id)) {
        return NEW_IASGN(id, val);
    }
    else if (is_const_id(id)) {
        if (in_def || in_single)
            yyerror("dynamic constant assignment");
        return NEW_CDECL(id, val, 0);
    }
    else if (is_class_id(id)) {
        if (in_def || in_single) return NEW_CVASGN(id, val);
        return NEW_CVDECL(id, val);
    }
    else {
        /* FIXME: indicate which identifier. */
        rb_compile_error("identifier is not valid 2 (%d)\n", id);
    }
    return 0;
}

static NODE *
aryset(recv, idx, parse_state)
    NODE *recv, *idx;
    rb_parse_state *parse_state;
{
    if (recv && nd_type(recv) == NODE_SELF)
        recv = (NODE *)1;
    else
        value_expr(recv);
    return NEW_ATTRASGN(recv, convert_op(tASET), idx);
}


static ID
rb_id_attrset(id)
    ID id;
{
    id &= ~ID_SCOPE_MASK;
    id |= ID_ATTRSET;
    return id;
}

static NODE *
attrset(recv, id, parse_state)
    NODE *recv;
    ID id;
    rb_parse_state *parse_state;
{
    if (recv && nd_type(recv) == NODE_SELF)
        recv = (NODE *)1;
    else
        value_expr(recv);
    return NEW_ATTRASGN(recv, rb_id_attrset(id), 0);
}

static void
rb_backref_error(node)
    NODE *node;
{
    switch (nd_type(node)) {
      case NODE_NTH_REF:
        rb_compile_error("Can't set variable $%u", node->nd_nth);
        break;
      case NODE_BACK_REF:
        rb_compile_error("Can't set variable $%c", (int)node->nd_nth);
        break;
    }
}

static NODE *
arg_concat(parse_state, node1, node2)
    rb_parse_state *parse_state;
    NODE *node1;
    NODE *node2;
{
    if (!node2) return node1;
    return NEW_ARGSCAT(node1, node2);
}

static NODE *
arg_add(parse_state, node1, node2)
    rb_parse_state *parse_state;
    NODE *node1;
    NODE *node2;
{
    if (!node1) return NEW_LIST(node2);
    if (nd_type(node1) == NODE_ARRAY) {
        return list_append(parse_state, node1, node2);
    }
    else {
        return NEW_ARGSPUSH(node1, node2);
    }
}

static NODE*
node_assign(lhs, rhs, parse_state)
    NODE *lhs, *rhs;
    rb_parse_state *parse_state;
{
    if (!lhs) return 0;

    value_expr(rhs);
    switch (nd_type(lhs)) {
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_DASGN_CURR:
      case NODE_MASGN:
      case NODE_CDECL:
      case NODE_CVDECL:
      case NODE_CVASGN:
        lhs->nd_value = rhs;
        break;

      case NODE_ATTRASGN:
      case NODE_CALL:
        lhs->nd_args = arg_add(parse_state, lhs->nd_args, rhs);
        break;

      default:
        /* should not happen */
        break;
    }

    return lhs;
}

static int
value_expr0(node, parse_state)
    NODE *node;
    rb_parse_state *parse_state;
{
    int cond = 0;

    while (node) {
        switch (nd_type(node)) {
          case NODE_DEFN:
          case NODE_DEFS:
            parser_warning(parse_state, node, "void value expression");
            return FALSE;

          case NODE_RETURN:
          case NODE_BREAK:
          case NODE_NEXT:
          case NODE_REDO:
          case NODE_RETRY:
            if (!cond) yyerror("void value expression");
            /* or "control never reach"? */
            return FALSE;

          case NODE_BLOCK:
            while (node->nd_next) {
                node = node->nd_next;
            }
            node = node->nd_head;
            break;

          case NODE_BEGIN:
            node = node->nd_body;
            break;

          case NODE_IF:
            if (!value_expr(node->nd_body)) return FALSE;
            node = node->nd_else;
            break;

          case NODE_AND:
          case NODE_OR:
            cond = 1;
            node = node->nd_2nd;
            break;

          case NODE_NEWLINE:
            node = node->nd_next;
            break;

          default:
            return TRUE;
        }
    }

    return TRUE;
}

static void
void_expr0(node)
    NODE *node;
{
  const char *useless = NULL;

    if (!RTEST(ruby_verbose)) return;

  again:
    if (!node) return;
    switch (nd_type(node)) {
      case NODE_NEWLINE:
        node = node->nd_next;
        goto again;

      case NODE_CALL:
        switch (node->nd_mid) {
          case '+':
          case '-':
          case '*':
          case '/':
          case '%':
          case tPOW:
          case tUPLUS:
          case tUMINUS:
          case '|':
          case '^':
          case '&':
          case tCMP:
          case '>':
          case tGEQ:
          case '<':
          case tLEQ:
          case tEQ:
          case tNEQ:
            useless = "";
            break;
        }
        break;

      case NODE_LVAR:
      case NODE_DVAR:
      case NODE_GVAR:
      case NODE_IVAR:
      case NODE_CVAR:
      case NODE_NTH_REF:
      case NODE_BACK_REF:
        useless = "a variable";
        break;
      case NODE_CONST:
      case NODE_CREF:
        useless = "a constant";
        break;
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
        useless = "a literal";
        break;
      case NODE_COLON2:
      case NODE_COLON3:
        useless = "::";
        break;
      case NODE_DOT2:
        useless = "..";
        break;
      case NODE_DOT3:
        useless = "...";
        break;
      case NODE_SELF:
        useless = "self";
        break;
      case NODE_NIL:
        useless = "nil";
        break;
      case NODE_TRUE:
        useless = "true";
        break;
      case NODE_FALSE:
        useless = "false";
        break;
      case NODE_DEFINED:
        useless = "defined?";
        break;
    }

    if (useless) {
        int line = ruby_sourceline;

        ruby_sourceline = nd_line(node);
        rb_warn("useless use of %s in void context", useless);
        ruby_sourceline = line;
    }
}

static void
void_stmts(node, parse_state)
    NODE *node;
    rb_parse_state *parse_state;
{
    if (!RTEST(ruby_verbose)) return;
    if (!node) return;
    if (nd_type(node) != NODE_BLOCK) return;

    for (;;) {
        if (!node->nd_next) return;
        void_expr(node->nd_head);
        node = node->nd_next;
    }
}

static NODE *
remove_begin(node)
    NODE *node;
{
    NODE **n = &node;
    while (*n) {
        switch (nd_type(*n)) {
          case NODE_NEWLINE:
            n = &(*n)->nd_next;
            continue;
          case NODE_BEGIN:
            *n = (*n)->nd_body;
          default:
            return node;
        }
    }
    return node;
}

static int
assign_in_cond(node, parse_state)
    NODE *node;
    rb_parse_state *parse_state;
{
    switch (nd_type(node)) {
      case NODE_MASGN:
        yyerror("multiple assignment in conditional");
        return 1;

      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_GASGN:
      case NODE_IASGN:
        break;

      case NODE_NEWLINE:
      default:
        return 0;
    }

    switch (nd_type(node->nd_value)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_NIL:
      case NODE_TRUE:
      case NODE_FALSE:
        return 1;

      case NODE_DSTR:
      case NODE_XSTR:
      case NODE_DXSTR:
      case NODE_EVSTR:
      case NODE_DREGX:
      default:
        break;
    }
    return 1;
}

static int
e_option_supplied()
{
    if (strcmp(ruby_sourcefile, "-e") == 0)
        return TRUE;
    return FALSE;
}

static void
warn_unless_e_option(ps, node, str)
    rb_parse_state *ps;
    NODE *node;
    const char *str;
{
    if (!e_option_supplied()) parser_warning(ps, node, str);
}

static NODE *cond0();

static NODE*
range_op(node, parse_state)
    NODE *node;
    rb_parse_state *parse_state;
{
    enum node_type type;

    if (!e_option_supplied()) return node;
    if (node == 0) return 0;

    value_expr(node);
    node = cond0(node, parse_state);
    type = nd_type(node);
    if (type == NODE_NEWLINE) {
        node = node->nd_next;
        type = nd_type(node);
    }
    if (type == NODE_LIT && FIXNUM_P(node->nd_lit)) {
        warn_unless_e_option(parse_state, node, "integer literal in conditional range");
        return call_op(node,tEQ,1,NEW_GVAR(rb_intern("$.")), parse_state);
    }
    return node;
}

static int
literal_node(node)
    NODE *node;
{
    if (!node) return 1;        /* same as NODE_NIL */
    switch (nd_type(node)) {
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_DREGX:
      case NODE_DREGX_ONCE:
      case NODE_DSYM:
        return 2;
      case NODE_TRUE:
      case NODE_FALSE:
      case NODE_NIL:
        return 1;
    }
    return 0;
}

static NODE*
cond0(node, parse_state)
    NODE *node;
    rb_parse_state *parse_state;
{
    if (node == 0) return 0;
    assign_in_cond(node, parse_state);

    switch (nd_type(node)) {
      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_STR:
        break;

      case NODE_DREGX:
      case NODE_DREGX_ONCE:
        local_cnt('_');
        local_cnt('~');
        return NEW_MATCH2(node, NEW_GVAR(rb_intern("$_")));

      case NODE_AND:
      case NODE_OR:
        node->nd_1st = cond0(node->nd_1st, parse_state);
        node->nd_2nd = cond0(node->nd_2nd, parse_state);
        break;

      case NODE_DOT2:
      case NODE_DOT3:
        node->nd_beg = range_op(node->nd_beg, parse_state);
        node->nd_end = range_op(node->nd_end, parse_state);
        if (nd_type(node) == NODE_DOT2) nd_set_type(node,NODE_FLIP2);
        else if (nd_type(node) == NODE_DOT3) nd_set_type(node, NODE_FLIP3);
        if (!e_option_supplied()) {
            int b = literal_node(node->nd_beg);
            int e = literal_node(node->nd_end);
            if ((b == 1 && e == 1) || (b + e >= 2 && RTEST(ruby_verbose))) {
            }
        }
        break;

      case NODE_DSYM:
        break;

      case NODE_REGEX:
        nd_set_type(node, NODE_MATCH);
        local_cnt('_');
        local_cnt('~');
      default:
        break;
    }
    return node;
}

static NODE*
cond(node, parse_state)
    NODE *node;
    rb_parse_state *parse_state;
{
    if (node == 0) return 0;
    value_expr(node);
    if (nd_type(node) == NODE_NEWLINE){
        node->nd_next = cond0(node->nd_next, parse_state);
        return node;
    }
    return cond0(node, parse_state);
}

static NODE*
logop(type, left, right, parse_state)
    enum node_type type;
    NODE *left, *right;
    rb_parse_state *parse_state;
{
    value_expr(left);
    if (left && nd_type(left) == type) {
        NODE *node = left, *second;
        while ((second = node->nd_2nd) != 0 && nd_type(second) == type) {
            node = second;
        }
        node->nd_2nd = NEW_NODE(type, second, right, 0);
        return left;
    }
    return NEW_NODE(type, left, right, 0);
}

static int
cond_negative(nodep)
    NODE **nodep;
{
    NODE *c = *nodep;

    if (!c) return 0;
    switch (nd_type(c)) {
      case NODE_NOT:
        *nodep = c->nd_body;
        return 1;
      case NODE_NEWLINE:
        if (c->nd_next && nd_type(c->nd_next) == NODE_NOT) {
            c->nd_next = c->nd_next->nd_body;
            return 1;
        }
    }
    return 0;
}

static void
no_blockarg(node)
    NODE *node;
{
    if (node && nd_type(node) == NODE_BLOCK_PASS) {
        rb_compile_error("block argument should not be given");
    }
}

static NODE *
ret_args(parse_state, node)
    rb_parse_state *parse_state;
    NODE *node;
{
    if (node) {
        no_blockarg(node);
        if (nd_type(node) == NODE_ARRAY && node->nd_next == 0) {
            node = node->nd_head;
        }
        if (node && nd_type(node) == NODE_SPLAT) {
            node = NEW_SVALUE(node);
        }
    }
    return node;
}

static NODE *
new_yield(parse_state, node)
    rb_parse_state *parse_state;
    NODE *node;
{
    OBJECT state = Qtrue;

    if (node) {
        no_blockarg(node);
        if (nd_type(node) == NODE_ARRAY && node->nd_next == 0) {
            node = node->nd_head;
            state = Qfalse;
        }
        if (node && nd_type(node) == NODE_SPLAT) {
            state = Qtrue;
        }
    }
    else {
        state = Qfalse;
    }
    return NEW_YIELD(node, state);
}

static NODE *
arg_blk_pass(node1, node2)
    NODE *node1;
    NODE *node2;
{
    if (node2) {
        node2->nd_head = node1;
        return node2;
    }
    return node1;
}

static NODE*
arg_prepend(parse_state, node1, node2)
    rb_parse_state *parse_state;
    NODE *node1, *node2;
{
    switch (nd_type(node2)) {
      case NODE_ARRAY:
        return list_concat(NEW_LIST(node1), node2);

      case NODE_SPLAT:
        return arg_concat(parse_state, node1, node2->nd_head);

      case NODE_BLOCK_PASS:
        node2->nd_body = arg_prepend(parse_state, node1, node2->nd_body);
        return node2;

      default:
        printf("unknown nodetype(%d) for arg_prepend", nd_type(node2));
        abort();
    }
    return 0;                   /* not reached */
}

static NODE*
new_call(parse_state, r,m,a)
    rb_parse_state *parse_state;
    NODE *r;
    ID m;
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
        a->nd_iter = NEW_CALL(r,convert_op(m),a->nd_head);
        return a;
    }
    return NEW_CALL(r,convert_op(m),a);
}

static NODE*
new_fcall(parse_state, m,a)
    rb_parse_state *parse_state;
    ID m;
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
        a->nd_iter = NEW_FCALL(m,a->nd_head);
        return a;
    }
    return NEW_FCALL(m,a);
}

static NODE*
new_super(parse_state,a)
    rb_parse_state *parse_state;
    NODE *a;
{
    if (a && nd_type(a) == NODE_BLOCK_PASS) {
        a->nd_iter = NEW_SUPER(a->nd_head);
        return a;
    }
    return NEW_SUPER(a);
}


static void
syd_local_push(rb_parse_state *st, int top)
{
    st->variables = var_table_push(st->variables);
}

static void
syd_local_pop(rb_parse_state *st)
{
    st->variables = var_table_pop(st->variables);
}


static ID*
syd_local_tbl(rb_parse_state *st)
{
    ID *lcl_tbl;
    var_table tbl;
    int i, len;
    tbl = st->variables;
    len = var_table_size(tbl);
    lcl_tbl = pt_allocate(st, sizeof(ID) * (len + 3));
    lcl_tbl[0] = (ID)len;
    lcl_tbl[1] = '_';
    lcl_tbl[2] = '~';
    for(i = 0; i < len; i++) {
        lcl_tbl[i + 3] = var_table_get(tbl, i);
    }
    return lcl_tbl;
}

static intptr_t
syd_local_cnt(rb_parse_state *st, ID id)
{
    int idx;
    /* Leave these hardcoded here because they arne't REALLY ids at all. */
    if(id == '_') {
        return 0;
    } else if(id == '~') {
        return 1;
    }
    
    idx = var_table_find(st->variables, id);
    if(idx >= 0) return idx + 2;
    
    return var_table_add(st->variables, id);
}

static int
syd_local_id(rb_parse_state *st, ID id)
{
    if(var_table_find(st->variables, id) >= 0) return 1;
    return 0;
}

static ID
rb_intern(const char *name)
{
    const char *m = name;
    ID id, pre, qrk, bef;
    int last;
    
    id = 0;    
    last = strlen(name)-1;
    switch (*name) {
      case '$':
        id |= ID_GLOBAL;
        m++;
        if (!is_identchar(*m)) m++;
        break;
      case '@':
        if (name[1] == '@') {
            m++;
            id |= ID_CLASS;
        }
        else {
            id |= ID_INSTANCE;
        }
        m++;
        break;
      default:
        if (name[0] != '_' && !ISALPHA(name[0]) && !ismbchar(name[0])) {
            int i;

            for (i=0; op_tbl[i].token; i++) {
                if (*op_tbl[i].name == *name &&
                    strcmp(op_tbl[i].name, name) == 0) {
                    id = op_tbl[i].token;
                    return id;
                }
            }
        }

        if (name[last] == '=') {
            id = ID_ATTRSET;
        }
        else if (ISUPPER(name[0])) {
            id = ID_CONST;
        }
        else {
            id = ID_LOCAL;
        }
        break;
    }
    while (m <= name + last && is_identchar(*m)) {
        m += mbclen(*m);
    }
    if (*m) id = ID_JUNK;
    qrk = (ID)quark_from_string(name);
    pre = qrk + tLAST_TOKEN;
    bef = id;
    id |= ( pre << ID_SCOPE_SHIFT );
    return id;
}

quark id_to_quark(ID id) {
  quark qrk;
  
  qrk = (quark)((id >> ID_SCOPE_SHIFT) - tLAST_TOKEN);
  return qrk;
}

static unsigned long
scan_oct(const char *start, int len, int *retlen)
{
    register const char *s = start;
    register unsigned long retval = 0;

    while (len-- && *s >= '0' && *s <= '7') {
        retval <<= 3;
        retval |= *s++ - '0';
    }
    *retlen = s - start;
    return retval;
}

static unsigned long
scan_hex(const char *start, int len, int *retlen)
{
    static const char hexdigit[] = "0123456789abcdef0123456789ABCDEF";
    register const char *s = start;
    register unsigned long retval = 0;
    char *tmp;

    while (len-- && *s && (tmp = strchr(hexdigit, *s))) {
        retval <<= 4;
        retval |= (tmp - hexdigit) & 15;
        s++;
    }
    *retlen = s - start;
    return retval;
}

const char *op_to_name(ID id) {
  if(id < tLAST_TOKEN) {
    int i = 0;

    for (i=0; op_tbl[i].token; i++) {
        if (op_tbl[i].token == id)
            return op_tbl[i].name;
    }
  }
  return NULL;
}
