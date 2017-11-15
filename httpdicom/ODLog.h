//
//  ODLog.h
//  httpdicom
//
//  Created by jacquesfauquex on 2017-03-20.
//  Copyright © 2017 opendicom.com. All rights reserved.
//
#import <Foundation/Foundation.h>

//DEBUG          sql query + sql answer
//VERBOSE        sql query
//INFO           service invocación
//WARNING        outside normal behaviour
//ERROR          service not completed
//EXCEPTION      aplication needs restart

typedef NS_ENUM(int, ODLogLevelEnum) {
    ODLogLevel_Debug = 0,
    ODLogLevel_Verbose,
    ODLogLevel_Info,
    ODLogLevel_Warning,
    ODLogLevel_Error,
    ODLogLevel_Exception
};

extern ODLogLevelEnum ODLogLevel;
extern void ODLog(ODLogLevelEnum level, NSString* format, ...) NS_FORMAT_FUNCTION(2, 3);

#define LOG_DEBUG(...) do { if (ODLogLevel <= ODLogLevel_Debug) ODLog(ODLogLevel_Debug, __VA_ARGS__); } while (0)
#define LOG_VERBOSE(...) do { if (ODLogLevel <= ODLogLevel_Verbose) ODLog(ODLogLevel_Verbose, __VA_ARGS__); } while (0)
#define LOG_INFO(...) do { if (ODLogLevel <= ODLogLevel_Info) ODLog(ODLogLevel_Info, __VA_ARGS__); } while (0)
#define LOG_WARNING(...) do { if (ODLogLevel <= ODLogLevel_Warning) ODLog(ODLogLevel_Warning, __VA_ARGS__); } while (0)
#define LOG_ERROR(...) do { if (ODLogLevel <= ODLogLevel_Error) ODLog(ODLogLevel_Error, __VA_ARGS__); } while (0)
#define LOG_EXCEPTION(__EXCEPTION__) do { if (ODLogLevel <= ODLogLevel_Exception) ODLog(ODLogLevel_Exception, @"%@", __EXCEPTION__); } while (0)
