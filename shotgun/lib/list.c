#include <stdlib.h>

#include "shotgun/lib/shotgun.h"
#include "shotgun/lib/cpu.h"
#include "shotgun/lib/machine.h"
#include "shotgun/lib/tuple.h"
#include "shotgun/lib/methctx.h"
#include "shotgun/lib/object.h"
#include "shotgun/lib/bytearray.h"
#include "shotgun/lib/string.h"
#include "shotgun/lib/class.h"
#include "shotgun/lib/hash.h"
#include "shotgun/lib/symbol.h"
#include "shotgun/lib/list.h"

void Init_list(STATE) {
  BASIC_CLASS(list) = rbs_class_new(state, "List", ListFields, BASIC_CLASS(object));
  BASIC_CLASS(list_node) = rbs_class_new_with_namespace(state, "Node", 
    ListNodeFields, BASIC_CLASS(object), BASIC_CLASS(list));
}

OBJECT list_new(STATE) {
  OBJECT lst;
  
  lst = rbs_class_new_instance(state, BASIC_CLASS(list));  
  list_set_count(lst, I2N(0));
  
  return lst;
}

void list_append(STATE, OBJECT self, OBJECT obj) {
  OBJECT node, cur_front, cur_last;
   
  node = rbs_class_new_instance(state, BASIC_CLASS(list_node));
  list_node_set_object(node, obj);
  cur_last = list_get_last(self);
  
  if(!NIL_P(cur_last)) {
    list_node_set_next(cur_last, node);
  }
  
  list_set_last(self, node);
  
  cur_front = list_get_first(self);
  if(NIL_P(cur_front)) {
    list_set_first(self, node);
  }
  
  list_set_count(self, I2N(N2I(list_get_count(self)) + 1));
}

OBJECT list_shift(STATE, OBJECT self) {
  OBJECT node;
  
  if(list_empty_p(self)) return Qnil;

  list_set_count(self, I2N(N2I(list_get_count(self)) - 1));  
  node = list_get_first(self);
  list_set_first(self, list_node_get_next(node));
  
  if(list_get_last(self) == node) {
    list_set_last(self, Qnil);
  }
  return list_node_get_object(node);
}

int list_delete(STATE, OBJECT self, OBJECT obj) {
  OBJECT node, lst, nxt;
  int count, deleted;
  
  deleted = 0;
  count = 0;
  lst = Qnil;
  node = list_get_first(self);
  while(!NIL_P(node)) {
    nxt = list_node_get_next(node);
    
    if(list_node_get_object(node) == obj) {
      deleted++;
      if(NIL_P(lst)) {
        list_set_first(self, nxt);
      } else {
        list_node_set_next(lst, nxt);
      }
      if(list_get_last(self) == node) {
        list_set_last(self, lst);
      }
    } else {
      count++;
    }
   
    lst = node;
    node = nxt;
  }
  
  list_set_count(self, I2N(count));
  
  return deleted;
}
