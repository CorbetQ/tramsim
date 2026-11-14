/* Clock ALSA's null sink without altering any PCM samples. Godot resolves ALSA
 * functions through dlsym, so intercept that lookup as well as direct calls. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <time.h>
typedef long (*writefn)(void *, const void *, unsigned long);
typedef void *(*lookupfn)(void *, const char *);
static writefn original_write;
static lookupfn real_lookup;
static struct timespec deadline;
static int clock_started;
static long clocked_write(void *pcm, const void *buffer, unsigned long frames) {
 long result = original_write(pcm,buffer,frames);
 if(result>0) {
  if (!clock_started) { clock_gettime(CLOCK_MONOTONIC,&deadline); clock_started=1; }
  deadline.tv_nsec += result*1000000000L/48000;
  deadline.tv_sec += deadline.tv_nsec/1000000000L;
  deadline.tv_nsec %= 1000000000L;
  clock_nanosleep(CLOCK_MONOTONIC,TIMER_ABSTIME,&deadline,0);
 }
 return result;
}
void *dlsym(void *handle, const char *name) {
 if (!real_lookup) real_lookup=(lookupfn)dlvsym(RTLD_NEXT,"dlsym","GLIBC_2.2.5");
 void *result=real_lookup(handle,name);
 if (strcmp(name,"snd_pcm_writei")==0) { original_write=(writefn)result; return (void *)clocked_write; }
 return result;
}
