#include <stdarg.h>
#include "shotgun/lib/shotgun.h"
#include "shotgun/lib/tuple.h"

OBJECT tuple_enlarge(STATE, OBJECT tup, int inc) {
  int sz;
  OBJECT ns;
  sz = NUM_FIELDS(tup);
  if(tup->gc_zone == YoungObjectZone) {
    ns = tuple_new(state, sz + inc);
  } else {
    ns = NEW_OBJECT_MATURE(state->global->tuple, sz + inc);
  }
  object_copy_fields_from(state, tup, ns, 0, sz);
  return ns;
}

OBJECT tuple_dup(STATE, OBJECT tup) {
  OBJECT ns;
  
  ns = tuple_new(state, NUM_FIELDS(tup));
  object_copy_fields_from(state, tup, ns, 0, NUM_FIELDS(tup));
  
  return ns;
}

OBJECT tuple_new2(STATE, int n, ...) {
  va_list ar;
  OBJECT tup;
  int i;
  
  tup = tuple_new(state, n);
  
  va_start(ar, n);
  for(i = 0; i < n; i++) {
    tuple_put(state, tup, i, va_arg(ar, OBJECT));
  }
  va_end(ar);
  return tup;
}
