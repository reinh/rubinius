#include <stdlib.h>
#include <stdint.h>
#include "shotgun/lib/config_hash.h"


DEFINE_HASHTABLE_INSERT(ht_config_insert, struct tagbstring, struct tagbstring);
DEFINE_HASHTABLE_SEARCH(ht_config_search, struct tagbstring, struct tagbstring);
DEFINE_HASHTABLE_REMOVE(ht_config_remove, struct tagbstring, struct tagbstring);
unsigned int bstring_hash(const void * value)
{
  unsigned int retval = 0;
  int i = 0;
  for (; i < blength((const_bstring)value); ++i)
    {
      retval += 5*bchar((const_bstring)value, i);
    }
  return retval;
}

int bstring_eq(const void * value1, const void * value2)
{
  return biseq((const_bstring)value1, (const_bstring)value2);
}

struct hashtable * ht_config_create(unsigned int minsize)
{
  return create_hashtable(minsize, bstring_hash, bstring_eq);
}

void ht_config_destroy(struct hashtable *ht_config)
{
  struct hashtable_itr iter;
  hashtable_iterator_init(&iter, ht_config);

  do 
    {
      bdestroy((bstring)hashtable_iterator_key(&iter));
      bdestroy((bstring)hashtable_iterator_value(&iter));
    }
  while (hashtable_iterator_remove(&iter));
  hashtable_destroy(ht_config, 0);
}

DEFINE_HASHTABLE_INSERT(ht_vconfig_insert, int, void);
DEFINE_HASHTABLE_SEARCH(ht_vconfig_search, int, void);
DEFINE_HASHTABLE_REMOVE(ht_vconfig_remove, int, void);

static unsigned int int_hash(const void *value)
{
  unsigned int retval = 0x64a3b9ac; /* totally made up */

  retval ^= *(int*)value;

  return retval;
}

static int int_eq(const void *value1, const void *value2)
{
  return *(int*)value1 == *(int*)value2;
}

struct hashtable * ht_vconfig_create(unsigned int minsize)
{
  return create_hashtable(minsize, int_hash, int_eq);
}

void ht_vconfig_destroy(struct hashtable *ht_config)
{
  hashtable_destroy(ht_config, 0);
}

void ht_vconfig_each(struct hashtable *ht, void (*cb)(int key, void *val))
{
  struct hashtable_itr itr;

  hashtable_iterator_init(&itr, ht);
  do {
    if (itr.e) {
      cb((uintptr_t)hashtable_iterator_key(&itr), hashtable_iterator_value(&itr));
    }
  } while (hashtable_iterator_advance(&itr));
}
