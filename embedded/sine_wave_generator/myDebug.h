#ifndef myDebug_h
#define myDebug_h

#define debug true

#if debug
#define Dln(x) Serial.println(x)
#define D(x) Serial.print(x)
#define DTypeln(x,y) Serial.println(x,y)
#define DType(x,y) Serial.print(x,y)
#define Df(x,y) Serial.printf(x,y)
#else
#define Dln(x)
#define D(x)
#define DTypeln(x,y)
#define DType(x,y)
#define Df(x,y)
#endif

#endif
