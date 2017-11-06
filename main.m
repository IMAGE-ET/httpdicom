#import <Foundation/Foundation.h>
#import "ODLog.h"
//look at the implementation of the function ODLog below

#import "RS.h"
#import "RSDataResponse.h"
#import "RSErrorResponse.h"
#import "RSFileResponse.h"
#import "RSStreamedResponse.h"

#import "LFCGzipUtility.h"

#import "NSString+PCS.h"
#import "NSData+PCS.h"

#import "URLSessionDataTask.h"

/*
 Copyright:  Copyright (c) 2017 jacques.fauquex@opendicom.com All Rights Reserved.
 
 This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 If a copy of the MPL was not distributed with this file, You can obtain one at
 http://mozilla.org/MPL/2.0/
 
 Covered Software is provided under this License on an “as is” basis, without warranty of
 any kind, either expressed, implied, or statutory, including, without limitation,
 warranties that the Covered Software is free of defects, merchantable, fit for a particular
 purpose or non-infringing. The entire risk as to the quality and performance of the Covered
 Software is with You. Should any Covered Software prove defective in any respect, You (not
 any Contributor) assume the cost of any necessary servicing, repair, or correction. This
 disclaimer of warranty constitutes an essential part of this License. No use of any Covered
 Software is authorized under this License except under this disclaimer.
 
 Under no circumstances and under no legal theory, whether tort (including negligence),
 contract, or otherwise, shall any Contributor, or anyone who distributes Covered Software
 as permitted above, be liable to You for any direct, indirect, special, incidental, or
 consequential damages of any character including, without limitation, damages for lost
 profits, loss of goodwill, work stoppage, computer failure or malfunction, or any and all
 other commercial damages or losses, even if such party shall have been informed of the
 possibility of such damages. This limitation of liability shall not apply to liability for
 death or personal injury resulting from such party’s negligence to the extent applicable
 law prohibits such limitation. Some jurisdictions do not allow the exclusion or limitation
 of incidental or consequential damages, so this exclusion and limitation may not apply to
 You.
 */


//static immutable write
static uint32 zipLocalFileHeader=0x04034B50;
static uint16 zipVersion=0x0A;
static uint32 zipNameLength=0x28;
static uint32 zipFileHeader=0x02014B50;
static uint32 zipEndOfCentralDirectory=0x06054B50;
static NSTimeInterval timeout=300;

//static immutable find within NSData
static NSData *rn;
static NSData *rnrn;
static NSData *rnhh;
static NSData *contentType;
static NSData *CDAOpeningTag;
static NSData *CDAClosingTag;
static NSData *ctad;

//datatables caché [session]
static NSMutableDictionary *Date;
static NSMutableDictionary *Req;
static NSMutableDictionary *Total;
static NSMutableDictionary *Filtered;
static NSMutableDictionary *sPatientID;
static NSMutableDictionary *sPatientName;
static NSMutableDictionary *sDate_start;
static NSMutableDictionary *sDate_end;
static NSMutableDictionary *sModality;
static NSMutableDictionary *sStudyDescription;

int task(NSString *launchPath, NSArray *launchArgs, NSData *writeData, NSMutableData *readData)
{
    NSTask *task=[[NSTask alloc]init];
    [task setLaunchPath:launchPath];
    [task setArguments:launchArgs];
    //LOG_INFO(@"%@",[task arguments]);
    NSPipe *writePipe = [NSPipe pipe];
    NSFileHandle *writeHandle = [writePipe fileHandleForWriting];
    [task setStandardInput:writePipe];
    
    NSPipe* readPipe = [NSPipe pipe];
    NSFileHandle *readingFileHandle=[readPipe fileHandleForReading];
    [task setStandardOutput:readPipe];
    [task setStandardError:readPipe];
    
    [task launch];
    [writeHandle writeData:writeData];
    [writeHandle closeFile];
    
    NSData *dataPiped = nil;
    while((dataPiped = [readingFileHandle availableData]) && [dataPiped length])
    {
        [readData appendData:dataPiped];
    }
    //while( [task isRunning]) [NSThread sleepForTimeInterval: 0.1];
    //[task waitUntilExit];		// <- This is VERY DANGEROUS : the main runloop is continuing...
    //[aTask interrupt];
    
    [task waitUntilExit];
    int terminationStatus = [task terminationStatus];
    if (terminationStatus!=0) LOG_INFO(@"ERROR task terminationStatus: %d",terminationStatus);
    return terminationStatus;
}

NSMutableArray *jsonMutableArray(NSString *scriptString, NSStringEncoding encoding)
{
    if      (encoding==4) LOG_DEBUG(@"utf8\r\n%@",scriptString);
    else if (encoding==5) LOG_DEBUG(@"latin1\r\n%@",scriptString);
    else                  LOG_DEBUG(@"encoding:%lu\r\n%@",(unsigned long)encoding,scriptString);

    NSMutableData *mutableData=[NSMutableData data];
    if (!task(@"/bin/bash",@[@"-s"],[scriptString dataUsingEncoding:NSUTF8StringEncoding],mutableData))
    [RSErrorResponse responseWithClientError:404 message:@"%@",@"can not execute the script"];//NotFound
    NSString *string=[[NSString alloc]initWithData:mutableData encoding:encoding];//5=latinISO1 4=UTF8
    NSData *utf8Data=[string dataUsingEncoding:NSUTF8StringEncoding];

    NSError *e;
    NSMutableArray *mutableArray=[NSJSONSerialization JSONObjectWithData:utf8Data options:NSJSONReadingMutableContainers error:&e];
    if (e)
    {
        LOG_DEBUG(@"%@",[e description]);
        return nil;
    }
    return mutableArray;
}


id qidoUrlProxy(NSString *qidoString,NSString *queryString, NSString *httpdicomString)
{
    __block dispatch_semaphore_t __urlProxySemaphore = dispatch_semaphore_create(0);
    __block NSMutableData *__data;
    __block NSURLResponse *__response;
    __block NSError *__error;
    __block NSDate *__date;
    __block unsigned long __chunks=0;
    
    NSString *urlString;
    if (queryString) urlString=[NSString stringWithFormat:@"%@?%@",qidoString,queryString];
    else urlString=qidoString;

    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];//application/dicom+json not accepted !!!!!
    
    NSURLSessionDataTask * const dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
                                             {
                                                 __data=[NSMutableData dataWithData:data];
                                                 __response=response;
                                                 __error=error;
                                                 dispatch_semaphore_signal(__urlProxySemaphore);
                                             }];
    __date=[NSDate date];
    [dataTask resume];
    dispatch_semaphore_wait(__urlProxySemaphore, DISPATCH_TIME_FOREVER);
    //completionHandler of dataTask executed only once and before returning
    return [RSStreamedResponse responseWithContentType:@"application/json" asyncStreamBlock:^(RSBodyReaderCompletionBlock completionBlock)
            {
                if (__error) completionBlock(nil,__error);
                if (__chunks)
                {
                    completionBlock([NSData data], nil);
                    LOG_DEBUG(@"urlProxy: %lu chunk in %fs for:\r\n%@",__chunks,[[NSDate date] timeIntervalSinceDate:__date],[__response description]);
                }
                else
                {
                    NSData *pacsUri=[qidoString dataUsingEncoding:NSUTF8StringEncoding];
                    NSData *httpdicomUri=[httpdicomString dataUsingEncoding:NSUTF8StringEncoding];
                    NSUInteger httpdicomLength=[httpdicomUri length];
                    NSRange dataLeft=NSMakeRange(0,[__data length]);
                    NSRange occurrence=[__data rangeOfData:pacsUri options:0 range:dataLeft];
                    while (occurrence.length)
                    {
                        [__data replaceBytesInRange:occurrence
                                          withBytes:[httpdicomUri bytes]
                                             length:httpdicomLength];
                        dataLeft.location=occurrence.location+httpdicomLength;
                        dataLeft.length=[__data length]-dataLeft.location;
                        occurrence=[__data rangeOfData:pacsUri options:0 range:dataLeft];
                    }
                    completionBlock(__data, nil);
                    __chunks++;
                }
            }];
}


id urlProxy(NSString *urlString,NSString *contentType)
{
    __block dispatch_semaphore_t __urlProxySemaphore = dispatch_semaphore_create(0);
    __block NSData *__data;
    __block NSURLResponse *__response;
    __block NSError *__error;
    __block NSDate *__date;
    __block unsigned long __chunks=0;
    
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    if (contentType) [request setValue:contentType forHTTPHeaderField:@"Accept"];//application/dicom+json not accepted !!!!!

    NSURLSessionDataTask * const dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
                                             {
                                                 __data=data;
                                                 __response=response;
                                                 __error=error;
                                                 dispatch_semaphore_signal(__urlProxySemaphore);
                                             }];
    __date=[NSDate date];
    [dataTask resume];
    dispatch_semaphore_wait(__urlProxySemaphore, DISPATCH_TIME_FOREVER);
    //completionHandler of dataTask executed only once and before returning

    
    return [RSStreamedResponse responseWithContentType:contentType asyncStreamBlock:^(RSBodyReaderCompletionBlock completionBlock)
            {
                if (__error) completionBlock(nil,__error);
                if (__chunks)
                {
                    completionBlock([NSData data], nil);
                    LOG_DEBUG(@"urlProxy: %lu chunk in %fs for:\r\n%@",__chunks,[[NSDate date] timeIntervalSinceDate:__date],[__response description]);
                }
                else completionBlock(__data, nil);
                __chunks++;
            }];
}

id urlChunkedProxy(NSString *urlString,NSString *contentType)
{
    __block dispatch_semaphore_t __urlProxySemaphore = dispatch_semaphore_create(0);
    __block NSData *__data;
    __block NSURLResponse *__response;
    __block NSError *__error;
    __block NSDate *__date;
    __block unsigned long __chunks=0;
    
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setValue:contentType forHTTPHeaderField:@"Accept"];//application/dicom+json not accepted !!!!!
    [request setValue:@"chunked" forHTTPHeaderField:@"Transfer-Encoding"];
    
    NSURLSessionDataTask * const dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
                                             {
                                                 __data=data;
                                                 __response=response;
                                                 __error=error;
                                                 dispatch_semaphore_signal(__urlProxySemaphore);
                                             }];
    __date=[NSDate date];
    [dataTask resume];
    dispatch_semaphore_wait(__urlProxySemaphore, DISPATCH_TIME_FOREVER);
    //completionHandler of dataTask executed only once and before returning
    
    
    return [RSStreamedResponse responseWithContentType:contentType asyncStreamBlock:^(RSBodyReaderCompletionBlock completionBlock)
            {
                if (__error) completionBlock(nil,__error);
                if (__chunks)
                {
                    completionBlock([NSData data], nil);
                    LOG_DEBUG(@"urlProxy: %lu chunk in %fs for:\r\n%@",__chunks,[[NSDate date] timeIntervalSinceDate:__date],[__response description]);
                }
                else completionBlock(__data, nil);
                __chunks++;
            }];
}

ODLogLevelEnum ODLogLevel = ODLogLevel_Info;
static const char* levelNames[] = {"DEBUG", "VERBOSE", "INFO", "WARNING", "ERROR", "EXCEPTION"};
void ODLog(ODLogLevelEnum level, NSString* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    fprintf(stderr, "[%s] %s\n", levelNames[level], [message UTF8String]);
}

BOOL buildWhereString(BOOL E,BOOL S,BOOL I,NSArray *queryItems, NSDictionary *sqlDict, NSMutableString *whereString)
{

    return true;
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        
        
        /*
         syntax:
         [0] httpdicom
         [1] devicesplistpath
         [2] httpdicomport
         [3] loglevel [ DEBUG | VERBOSE | INFO | WARNING | ERROR | EXCEPTION]
         */
        NSArray *args=[[NSProcessInfo processInfo] arguments];
        if ([args count]!=4)
        {
            LOG_WARNING(@"syntax: httpdicom devicesplist httpdicomport loglevel");
            return 1;
        }
        
        
        //[3] loglevel
        NSUInteger llindex=[@[@"DEBUG",@"VERBOSE",@"INFO",@"WARNING",@"ERROR",@"EXCEPTION"] indexOfObject:args[3]];
        if (llindex==NSNotFound)
        {
            LOG_ERROR(@"ODLogLevel (arg 1) should be one of [ DEBUG | VERBOSE | INFO | WARNING | ERROR | EXCEPTION ]");
            return 1;
        }
        ODLogLevel=(int)llindex;
        
        
        //[2] httpdicomport
        long long port=[args[2]longLongValue];
        if (port <1 || port>65535)
        {
            LOG_ERROR(@"port should be between 0 and 65535");
            return 1;
        }
        
        //util formatters
        NSDateFormatter *dicomDTFormatter = [[NSDateFormatter alloc] init];
        [dicomDTFormatter setDateFormat:@"yyyyMMddHHmmss"];
        NSRegularExpression *UIRegex = [NSRegularExpression regularExpressionWithPattern:@"^[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*$" options:0 error:NULL];
        NSRegularExpression *SHRegex = [NSRegularExpression regularExpressionWithPattern:@"^(?:\\s*)([^\\r\\n\\f\\t]*[^\\r\\n\\f\\t\\s])(?:\\s*)$" options:0 error:NULL];
        
        //static immutable
        rn=[@"/r/n" dataUsingEncoding:NSASCIIStringEncoding];//0x0A0D;
        rnrn=[@"/r/n/r/n" dataUsingEncoding:NSASCIIStringEncoding];//0x0A0D0A0D;
        rnhh=[@"/r/n--" dataUsingEncoding:NSASCIIStringEncoding];//0x2D2D0A0D;
        contentType=[@"Content-Type: " dataUsingEncoding:NSASCIIStringEncoding];
        CDAOpeningTag=[@"<ClinicalDocument" dataUsingEncoding:NSASCIIStringEncoding];
        CDAClosingTag=[@"</ClinicalDocument>" dataUsingEncoding:NSASCIIStringEncoding];
        ctad=[@"Content-Type: application/dicom\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        
        //datatables caché [session]
        Req=[NSMutableDictionary dictionary];
        Total=[NSMutableDictionary dictionary];
        Filtered=[NSMutableDictionary dictionary];
        Date=[NSMutableDictionary dictionary];
        sPatientID=[NSMutableDictionary dictionary];
        sPatientName=[NSMutableDictionary dictionary];
        sDate_start=[NSMutableDictionary dictionary];
        sDate_end=[NSMutableDictionary dictionary];
        sModality=[NSMutableDictionary dictionary];
        sStudyDescription=[NSMutableDictionary dictionary];
        

        //[1] devicesplist (pacs is another name synonym of devices)
        NSDictionary *pacsDictionaries=[NSDictionary dictionaryWithContentsOfFile:[args[1]stringByExpandingTildeInPath]];
        if (!pacsDictionaries)
        {
            LOG_ERROR(@"could not get contents of pacs.plist");
            return 1;
        }
        //initialization of custodian and sql dictionaries based on properties of pacsDictionaries
        NSMutableDictionary *custodianoids=[NSMutableDictionary dictionary];
        NSMutableDictionary *custodiantitles=[NSMutableDictionary dictionary];
        NSMutableSet *sqlset=[NSMutableSet set];
        
        NSArray *pacsOids = [pacsDictionaries allValues];
        for (NSDictionary *d in pacsOids)
        {
            [custodianoids setObject:d[@"custodiantitle"] forKey:d[@"custodianoid"]];
            [custodiantitles setObject:d[@"custodianoid"] forKey:d[@"custodiantitle"]];
            NSString *s=[d objectForKey:@"sqldictpath"];
            if (s) [sqlset addObject:s];
        }
        //response data for root queries custodians/titles and custodians/oids
        NSData *custodianOIDsData = [NSJSONSerialization dataWithJSONObject:[custodianoids allKeys] options:0 error:nil];
        NSData *custodianTitlesData = [NSJSONSerialization dataWithJSONObject:[custodiantitles allKeys] options:0 error:nil];

        //devices OID classified by custodian
        NSMutableDictionary *custodianOIDsaeis=[NSMutableDictionary dictionary];
        for (NSString *custodianOID in [custodianoids allKeys])
        {
            NSMutableArray *custodianOIDaeis=[NSMutableArray array];
            for (NSString *k in [pacsDictionaries allKeys])
            {
                NSDictionary *d=[pacsDictionaries objectForKey:k];
                if ([[d objectForKey:@"custodianoid"]isEqualToString:custodianOID])[custodianOIDaeis addObject:k];
            }
            [custodianOIDsaeis setValue:custodianOIDaeis forKey:custodianOID];
        }
        LOG_VERBOSE(@"known devices OID classified by corresponding custodian OID:\r\n%@",[custodianOIDsaeis description]);

        //devices titles grouped on custodian
        NSMutableDictionary *custodianTitlesaets=[NSMutableDictionary dictionary];
        NSMutableDictionary *custodianTitlesaetsStrings=[NSMutableDictionary dictionary];
        for (NSString *custodianTitle in [custodiantitles allKeys])
        {
            NSMutableArray *custodianTitleaets=[NSMutableArray array];
            NSMutableString *s=[NSMutableString stringWithString:@"("];

            for (NSString *k in [pacsDictionaries allKeys])
            {
                NSDictionary *d=[pacsDictionaries objectForKey:k];
                if ([[d objectForKey:@"custodiantitle"]isEqualToString:custodianTitle])
                {
                    [custodianTitleaets addObject:[d objectForKey:@"dicomaet"]];
                    if ([s isEqualToString:@"("])
                        [s appendFormat:@"'%@'",[d objectForKey:@"dicomaet"]];
                    else [s appendFormat:@",'%@'",[d objectForKey:@"dicomaet"]];
                }
            }
            [custodianTitlesaets setObject:custodianTitleaets forKey:custodianTitle];
            [s appendString:@")"];
            [custodianTitlesaetsStrings setObject:s forKey:custodianTitle];
        }
        LOG_VERBOSE(@"known devices aet classified by corresponding custodian title:\r\n%@",[custodianTitlesaets description]);
        //LOG_VERBOSE(@"%@",custodianTitlesaetsStrings);

        NSMutableDictionary *pacsTitlesDictionary=[NSMutableDictionary dictionary];
        for (NSString *key in [pacsDictionaries allKeys])
        {
            [pacsTitlesDictionary setObject:key forKey:[(pacsDictionaries[key])[@"custodiantitle"] stringByAppendingPathExtension:(pacsDictionaries[key])[@"dicomaet"]]];
        }
        //LOG_VERBOSE(@"%@",[pacsTitlesDictionary description]);
        
        
        
        //sql queries and sql qido filters
        LOG_VERBOSE(@"sqls:\r\n%@",[sqlset description]);
        NSMutableDictionary *sql=[NSMutableDictionary dictionary];
        NSMutableDictionary *sqlWadoTags=[NSMutableDictionary dictionary];
        for (NSString *s in sqlset)
        {
            NSDictionary *sqldict=[NSDictionary dictionaryWithContentsOfFile:[s stringByExpandingTildeInPath]];
            if (!sqldict)
            {
                LOG_ERROR(@"could not get contents of %@",s);
                return 1;
            }
            [sql setObject:sqldict forKey:s];
            //sql-qido dictionary tag -> keyword
            NSDictionary *wadoKeyword=(sql[s])[@"QidoAttrs"];
            if (wadoKeyword)
            {
                NSMutableDictionary *tagKeyword=[NSMutableDictionary dictionary];
                for (NSString *keyword in [wadoKeyword allKeys])
                {
                    [tagKeyword setObject:keyword forKey:(wadoKeyword[keyword])[@"tag"]];
                }
                [sqlWadoTags setObject:tagKeyword forKey:s];
            }
        }

        

#pragma mark -
#pragma mark routing regex LIFO list
        //httpserver init
        RS* httpdicomServer = [[RS alloc] init];
        
        
#pragma mark any
        NSRegularExpression *anyRegex = [NSRegularExpression regularExpressionWithPattern:@".*" options:0 error:NULL];
        [
         httpdicomServer addHandler:@"GET" regex:anyRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock)
         {completionBlock(^RSResponse* (RSRequest* request){
            
            LOG_INFO(@"%@ no handler for path: %@",request.remoteAddressString,request.path);
            return [RSErrorResponse responseWithClientError:400 message:@"no handler for path: %@",request.path];
        
        }(request));}];

        
#pragma mark echo
        NSRegularExpression *echoRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/echo$" options:0 error:NULL];
        [httpdicomServer addHandler:@"GET" regex:echoRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock)
         {completionBlock(^RSResponse* (RSRequest* request){
            
            LOG_INFO(@"%@ echo",request.remoteAddressString);
            return [RSDataResponse responseWithText:request.remoteAddressString];
            
        }(request));}];
        

#pragma mark custodians
        NSRegularExpression *custodiansRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/custodians/.*$" options:0 error:NULL];
        [httpdicomServer addHandler:@"GET" regex:custodiansRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock)
         {completionBlock(^RSResponse* (RSRequest* request){
            
            LOG_DEBUG(@"client: %@",request.remoteAddressString);
            NSArray *pComponents=[request.path componentsSeparatedByString:@"/"];
             NSUInteger pCount=[pComponents count];
             
             if (pCount<3) return [RSErrorResponse responseWithClientError:400 message:@"%@ [no handler]",request.path];
             
             if ([pComponents[2]isEqualToString:@"titles"])
             {
                 //custodians/titles
                 if (pCount==3) return [RSDataResponse responseWithData:custodianTitlesData contentType:@"application/json"];
                 
                 NSUInteger p3Length = [pComponents[3] length];
                 if (  (p3Length>16)
                     ||![SHRegex numberOfMatchesInString:pComponents[3] options:0 range:NSMakeRange(0,p3Length)])
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{title} datatype should be DICOM SH]",request.path];
                 
                 if (!custodiantitles[pComponents[3]])
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{title} not found]",request.path];
                 
                 //custodians/titles/{TITLE}
                 if (pCount==4) return [RSDataResponse responseWithData:[NSJSONSerialization dataWithJSONObject:[NSArray arrayWithObject:custodiantitles[pComponents[3]]] options:0 error:nil] contentType:@"application/json"];
                 
                 if (![pComponents[4]isEqualToString:@"aets"])
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{title} unique resource is 'aets']",request.path];
                 
                 //custodians/titles/{title}/aets
                 if (pCount==5)
                     return [RSDataResponse responseWithData:[NSJSONSerialization dataWithJSONObject:[custodianTitlesaets objectForKey:pComponents[3]] options:0 error:nil] contentType:@"application/json"];

                 NSUInteger p5Length = [pComponents[5]length];
                 if (  (p5Length>16)
                     ||![SHRegex numberOfMatchesInString:pComponents[5] options:0 range:NSMakeRange(0,p5Length)])
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{aet}datatype should be DICOM SH]",request.path];
                 
                 NSUInteger aetIndex=[[custodianTitlesaets objectForKey:pComponents[3]] indexOfObject:pComponents[5]];
                 if (aetIndex==NSNotFound)
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{aet} not found]",request.path];

                 if (pCount>6) return [RSErrorResponse responseWithClientError:400 message:@"%@ [no handler]",request.path];

                 //custodians/titles/{title}/aets/{aet}
                     return [RSDataResponse responseWithData:
                             [NSJSONSerialization dataWithJSONObject:
                              [NSArray arrayWithObject:(custodianOIDsaeis[custodiantitles[pComponents[3]]])[aetIndex]]
                              options:0
                              error:nil
                             ]
                             contentType:@"application/json"
                            ];
             }
             
             
             if ([pComponents[2]isEqualToString:@"oids"])
             {
                 //custodians/oids
                 if (pCount==3) return [RSDataResponse responseWithData:custodianOIDsData contentType:@"application/json"];
                 
                 NSUInteger p3Length = [pComponents[3] length];
                 if (  (p3Length>64)
                     ||![UIRegex numberOfMatchesInString:pComponents[3] options:0 range:NSMakeRange(0,p3Length)]
                     )
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{OID} datatype should be DICOM UI]",request.path];
                 
                 if (!custodianoids[pComponents[3]])
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{OID} not found]",request.path];
                 
                 //custodian/oids/{OID}
                 if (pCount==4) return [RSDataResponse responseWithData:[NSJSONSerialization dataWithJSONObject:[NSArray arrayWithObject:custodianoids[pComponents[3]]] options:0 error:nil] contentType:@"application/json"];
                 
                 if (![pComponents[4]isEqualToString:@"aeis"])
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{OID} unique resource is 'aeis']",request.path];
                 
                 //custodian/oids/{OID}/aeis
                 if (pCount==5)
                     return [RSDataResponse responseWithData:[NSJSONSerialization dataWithJSONObject:[custodianOIDsaeis objectForKey:pComponents[3]] options:0 error:nil] contentType:@"application/json"];
                 
                 NSUInteger p5Length = [pComponents[5]length];
                 if (  (p5Length>64)
                     ||![UIRegex numberOfMatchesInString:pComponents[5] options:0 range:NSMakeRange(0,p5Length)]
                     )
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{aei}datatype should be DICOM UI]",request.path];
                 
                 NSUInteger aeiIndex=[[custodianOIDsaeis objectForKey:pComponents[3]] indexOfObject:pComponents[5]];
                 if (aeiIndex==NSNotFound)
                     return [RSErrorResponse responseWithClientError:404 message:@"%@ [{aei} not found]",request.path];
                 
                 if (pCount>6) return [RSErrorResponse responseWithClientError:400 message:@"%@ [no handler]",request.path];
                 
                 //custodian/oids/{OID}/aeis/{aei}
                 return [RSDataResponse responseWithData:
                         [NSJSONSerialization dataWithJSONObject:
                          [NSArray arrayWithObject:(pacsDictionaries[pComponents[5]])[@"dicomaet"]]
                                                         options:0
                                                           error:nil
                          ]
                                                       contentType:@"application/json"
                         ];
             }
             return [RSErrorResponse responseWithClientError:404 message:@"%@ [no handler]",request.path];

        }(request));}];

        
#pragma mark QIDO
        // /pacs/{oid}/rs/( studies | series | instances )?
        NSRegularExpression *qidoRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/pacs\\/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*\\/rs\\/(studies|series|instances)$" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandler:@"GET" regex:qidoRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];
             NSDictionary *pacsaei=pacsDictionaries[pComponents[2]];
             if (!pacsaei) return [RSErrorResponse responseWithClientError:404 message:@"%@ [{pacs} not found]",request.path];

             NSString *pcsuri=pacsaei[@"custodianbaseuri"];

             NSString *q=request.URL.query;//a same param may repeat

//use case where sql exists in pacs (therefore pacs is local)
             NSDictionary *destSql=sql[pacsaei[@"sqldictpath"]];
             if (destSql)
             {
                 
                 //local ... simulation qido through database access
                 
                 //create where
                 NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
                 NSUInteger level=[@[@"patients",@"studies",@"series",@"instances"] indexOfObject:pComponents[4]];
                 
                 
                 NSMutableString *whereString = [NSMutableString string];
                 switch (level) {
                     case 1:
                         [whereString appendString:destSql[@"studiesWhere"]];
                         break;
                     case 2:
                         [whereString appendString:destSql[@"seriesWhere"]];
                         break;
                     case 3:
                         [whereString appendString:destSql[@"instancesWhere"]];
                         break;
                     default:
                         [RSErrorResponse responseWithClientError:404 message:@"level %@ not accepted. Should be Study, Series or Instance",pComponents[4]];
                         break;
                 }
                 
                 
                 NSArray *queryItems=[urlComponents queryItems];
                 NSDictionary *qidoKeywordsDict=destSql[@"QidoAttrs"];
                 if ([queryItems count])
                 {
                     NSDictionary *qidoTags=sqlWadoTags[pacsaei[@"sqldictpath"]];
                     
                     for (NSURLQueryItem *qi in queryItems) {
                         
                         //keyword, keywordProperties
                         NSString *keyword=qidoTags[qi.name];//by tags
                         NSDictionary *keywordProperties=nil;
                         if (keyword) keywordProperties=qidoKeywordsDict[keyword];
                         else if (qidoKeywordsDict[qi.name])
                         {
                             keyword=qi.name;
                             keywordProperties=qidoKeywordsDict[qi.name];
                         }
                         else return [RSErrorResponse responseWithClientError:404 message:@"%@ [not a valid qido filter for this PACS]",qi.name];
                         
                         //level check
                         if ( level < [keywordProperties[@"level"] unsignedIntegerValue]) return [RSErrorResponse responseWithClientError:404 message:@"%@ [not available at level %@]",qi.name,pComponents[4]];
                         
                         //string compare
                         if ([@[@"LO",@"PN",@"CS",@"UI"] indexOfObject:keywordProperties[@"vr"]]!=NSNotFound)
                         {
                             [whereString appendString:
                              [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                               fieldString:destSql[keyword]
                                               valueString:qi.value
                               ]
                              ];
                             continue;
                         }
                         
                         
                         //date compare
                         if ([@[@"DA"] indexOfObject:keywordProperties[@"vr"]]!=NSNotFound)
                         {
                             NSArray *startEnd=[qi.value componentsSeparatedByString:@"-"];
                             switch ([startEnd count]) {
                                 case 1:;
                                 [whereString appendString:[destSql[keyword] sqlFilterWithStart:startEnd[0] end:startEnd[0]]];
                                 break;
                                 case 2:;
                                    [whereString appendString:[destSql[keyword] sqlFilterWithStart:startEnd[0] end:startEnd[1]]];
                                 break;
                             }
                             continue;
                         }
                         
                     }//end loop
                     
                 }//end queryItems
                 
                 
                 NSString *scriptString=nil;
                 switch (level) {
                     case 1:
                         scriptString=[NSString stringWithFormat:@"%@%@%@%@",
                                       pacsaei[@"sqlprolog"],
                                       destSql[@"QidoStudyProlog"],
                                       whereString,
                                       destSql[@"QidoStudyEpilog"]
                                       ];
                         break;
                     case 2:
                         scriptString=[NSString stringWithFormat:@"%@%@%@%@",
                                       pacsaei[@"sqlprolog"],
                                       destSql[@"QidoSeriesProlog"],
                                       whereString,
                                       destSql[@"QidoSeriesEpilog"]
                                       ];
                         break;
                     case 3:
                         scriptString=[NSString stringWithFormat:@"%@%@%@%@",
                                       pacsaei[@"sqlprolog"],
                                       destSql[@"QidoInstanceProlog"],
                                       whereString,
                                       destSql[@"QidoInstanceEpilog"]
                                       ];
                         break;
                 }
                 
                 
                 LOG_DEBUG(@"%@",scriptString);
                 
                 NSMutableData *mutableData=[NSMutableData data];
                 if (!task(@"/bin/bash",@[@"-s"],[scriptString dataUsingEncoding:NSUTF8StringEncoding],mutableData))
                     [RSErrorResponse responseWithClientError:404 message:@"%@",@"can not execute the script"];//NotFound

                 //db response may be in latin1
                 NSStringEncoding charset=(NSStringEncoding)[pacsaei[@"sqlstringencoding"] longLongValue ];
                 if (charset!=4 && charset!=5) return [RSErrorResponse responseWithClientError:404 message:@"unknown sql charset : %lu",(unsigned long)charset];
                 
                 if (charset==5) //latin1
                 {
                     NSString *latin1String=[[NSString alloc]initWithData:mutableData encoding:NSISOLatin1StringEncoding];
                     [mutableData setData:[latin1String dataUsingEncoding:NSUTF8StringEncoding]];
                 }
                 
                 NSError *error=nil;
                 NSMutableArray *arrayOfDicts=[NSJSONSerialization JSONObjectWithData:mutableData options:0 error:&error];
                 if (error) return [RSErrorResponse responseWithClientError:404 message:@"bad qido sql result : %@",[error description]];
                 
                 //formato JSON qido
                 NSMutableArray *qidoResponseArray=[NSMutableArray array];
                 for (NSDictionary *dict in arrayOfDicts)
                 {
                     NSMutableDictionary *object=[NSMutableDictionary dictionary];
                     for (NSString *key in dict)
                     {
                         NSDictionary *attrDesc=qidoKeywordsDict[key];
                         NSMutableDictionary *attrInst=[NSMutableDictionary dictionary];
                         if ([attrDesc[@"vr"] isEqualToString:@"PN"])
                             [attrInst setObject:@[@{@"Alphabetic":dict[key]}] forKey:@"Value"];
                         else if ([attrDesc[@"vr"] isEqualToString:@"DA"]) [attrInst setObject:@[[dict[key] dcmDaFromDate]] forKey:@"Value"];
                         else [attrInst setObject:@[dict[key]] forKey:@"Value"];
                         //TODO add other cases, like TM, DT, etc...
                         
                         [attrInst setObject:attrDesc[@"vr"] forKey:@"vr"];
                         [object setObject:attrInst forKey:attrDesc[@"tag"]];
                     }
                     [qidoResponseArray addObject:object];
                 }
                 NSData *j=[NSJSONSerialization dataWithJSONObject:qidoResponseArray
                                                           options:0
                                                             error:nil
                            ];
                 return [RSDataResponse responseWithData:
                         [NSJSONSerialization dataWithJSONObject:qidoResponseArray
                                                         options:0
                                                           error:nil
                          ]
                                             contentType:@"application/json"
                         ];
             }
             
             //there is no destSql

//use case where qido exists in pacs (pacs may be remote)
             NSString *qidoBaseString=pacsaei[@"qido"];
             if (![qidoBaseString isEqualToString:@""])
             {
                 return qidoUrlProxy(
                                 [NSString stringWithFormat:@"%@/%@",qidoBaseString,pComponents.lastObject],
                                 q,
                                     [pcsuri stringByAppendingString:request.path]
                                 );//application/dicom+json not accepted
             }
             

             //use case where qido should be forwarded
             if (pcsuri)
             {
                 //remote... access through another PCS
                 NSString *urlString;
                 if (q) urlString=[NSString stringWithFormat:@"%@/%@?%@",
                                    pcsuri,
                                    request.path,
                                    q];
                 else    urlString=[NSString stringWithFormat:@"%@/%@?",
                                     pcsuri,
                                     request.path];
                 LOG_INFO(@"[QIDO] %@",urlString);
                 return urlProxy(urlString,@"application/dicom+json");
             }
             
             //otherwise
             return [RSErrorResponse responseWithClientError:404 message:@"%@ [QIDO not available]",request.path];
             
         }(request));}];
        
        
#pragma mark WADO-URI
        NSRegularExpression *wadouriRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/$" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandler:@"GET" regex:wadouriRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];

             //NSDictionary *pacsaei=pacsDictionaries[pComponents[2]];
             NSDictionary *pacsaei=pacsDictionaries[(request.query)[@"custodianOID"]];
             if (!pacsaei) return [RSErrorResponse responseWithClientError:404 message:@"%@ [{pacs} not found]",request.path];
             
             NSString *q=request.URL.query;//a same param may repeat

             NSString *wadouriBaseString=pacsaei[@"wadouri"];
             if (![wadouriBaseString isEqualToString:@""])
             {
                 //local ... there exists an URL
                 NSString *wadouriString;
                 if (q) wadouriString=[NSMutableString stringWithFormat:@"%@?%@",
                                    wadouriBaseString,
                                    q];
                 [wadouriString stringByReplacingOccurrencesOfString:@"%22" withString:@""];

                 LOG_INFO(@"[WADO-URI] %@",wadouriString);
                 //no se agrega ningún control para no enlentecer
                 //podría optimizarse con creación asíncrona de la data
                 //paquetes entran y salen sin esperar el fin de la entrada...
                 NSData *responseData=[NSData dataWithContentsOfURL:[NSURL URLWithString:wadouriString]];
                 if (!responseData) return
                     [RSErrorResponse
                      responseWithClientError:424
                      message:@"no reply"];//FailedDependency
                 
                 if (![responseData length]) return
                     [RSErrorResponse
                      responseWithClientError:404
                      message:@"empty reply"];//NotFound
                 return [RSDataResponse
                         responseWithData:responseData
                         contentType:@"application/dicom"
                         ];
             }
             
             NSString *pcsuri=pacsaei[@"pcsuri"];
             if (pcsuri)
             {
                 //remote... access through another PCS
                 NSString *urlString;
                 if (q) urlString=[NSString stringWithFormat:@"%@/%@",
                                   pcsuri,
                                   request.path];
                 else    urlString=[NSString stringWithFormat:@"%@/%@",
                                    pcsuri,
                                    request.path];
                 LOG_INFO(@"[QIDO] %@",urlString);
                 return urlProxy(urlString,@"application/dicom+json");
             }

             return [RSErrorResponse responseWithClientError:404 message:@"%@ [WADO-URI not available]",request.path];
                                                                                                                   
         }(request));}];
        
#pragma mark WADO-RS
        // /pacs/{OID}/studies/{StudyInstanceUID}
        // /pacs/{OID}/studies/{StudyInstanceUID}/series/{SeriesInstanceUID}
        // /pacs/{OID}/studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}
        //Accept: multipart/related;type="application/dicom"
        NSRegularExpression *wadorsRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/pacs\\/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*\\/rs\\/studies\\/" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandler:@"GET" regex:wadorsRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];

             NSDictionary *pacsaei=pacsDictionaries[pComponents[2]];
             if (!pacsaei) return [RSErrorResponse responseWithClientError:404 message:@"%@ [{pacs} not found]",request.path];

             NSString *wadorsBaseString=pacsaei[@"wadors"];
             if (![wadorsBaseString isEqualToString:@""])
             {
                 //local ... there exists an URI that uses the PACS implementation
                 NSString *urlString;
                 if (pComponents.count==6) urlString=[NSString stringWithFormat:@"%@/studies/%@",wadorsBaseString,pComponents[5]];
                 else if (pComponents.count==8) urlString=[NSString stringWithFormat:@"%@/studies/%@/series/%@", wadorsBaseString,pComponents[5],pComponents[7]];
                 else if (pComponents.count==10) urlString=[NSString stringWithFormat:@"%@/studies/%@/series/%@/instances/%@", wadorsBaseString,pComponents[5],pComponents[7],pComponents[9]];
                 else return [RSErrorResponse responseWithClientError:404 message:@"%@ [WADO-RS studies and studies/series only]",request.path];
                 LOG_INFO(@"[WADO-RS] %@",urlString);
                 return urlProxy(urlString,@"multipart/related;type=application/dicom");
             }
             
             NSString *sql=pacsaei[@"sqlQueriesDictionary"];
             if (sql)
             {
                 //local ... the PCS simulates wadors thanks to a combination of
                 //database access and wado-url
#pragma mark TODO WADO-RS SQL
             }
             
             NSString *pcsuri=pacsaei[@"pcsuri"];
             if (pcsuri)
             {
                 //when there is neither direct access to pacs implementation nor sql access in order to simulate the function, then we use the proxying services of another PCS accessed through pcsuri
                 NSString *urlString=[NSString stringWithFormat:@"%@/%@",pcsuri,request.path];
                 LOG_INFO(@"[WADO-RS] %@",urlString);
                 return urlProxy(urlString,@"multipart/related;type=application/dicom");
             }
             return [RSErrorResponse responseWithClientError:404 message:@"%@ [WADO-RS not available]",request.path];
             
         }(request));}];
        
#pragma mark dcm.zip
        ///pacs/{OID}/dcm.zip?
        //servicio de segundo nivel que llama a WADO-RS para su realización
        NSRegularExpression *dcmzipRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/pacs\\/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*\\/dcm.zip$" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandler:@"GET" regex:dcmzipRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
        {
            LOG_DEBUG(@"client: %@",request.remoteAddressString);
            //using NSURLComponents instead of RSRequest
            NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
            NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];

            NSDictionary *destPacs=pacsDictionaries[pComponents[2]];
            if (!destPacs) return [RSErrorResponse responseWithClientError:404 message:@"%@ [{pacs} not found]",request.path];

            LOG_VERBOSE(@"dcm.zip?%@",[urlComponents query]);
            
            NSDictionary *pacsaei=pacsDictionaries[pComponents[2]];
            //use case where sql exists in pacs (therefore pacs is local)
            NSDictionary *destSql=sql[pacsaei[@"sqlQueriesDictionary"]];


//          if (!destPacs[@"qido"] || [destPacs[@"qido"]isEqualToString:@""])
            if (destSql)
            {
                //sql + wado-uri

                //return [RSErrorResponse responseWithClientError:404 message:@"%@ [qido not available]",request.path];

                //sql instance level
                NSString *WadoUrisSqlString;
                NSString *AccessionNumber=request.query[@"AccessionNumber"];
                if (AccessionNumber)WadoUrisSqlString=[NSString stringWithFormat:destSql[@"studyAccessionNumberWadosUris"],AccessionNumber];
                else
                {
                    NSString *StudyInstanceUID=request.query[@"StudyInstanceUID"];
                    if (StudyInstanceUID)WadoUrisSqlString=[NSString stringWithFormat:destSql[@"studyUIDWadosUris"],StudyInstanceUID];
                    else
                    {
                        NSString *SeriesInstanceUID=request.query[@"SeriesInstanceUID"];
                        if (SeriesInstanceUID)WadoUrisSqlString=[NSString stringWithFormat:destSql[@"seriesUIDWadosUris"],SeriesInstanceUID];

                        else return [RSErrorResponse responseWithClientError:404 message:
                                 @"parameter AccessionNumber or StudyInstanceUID required"];
                    }
                }
                LOG_DEBUG(@"%@",WadoUrisSqlString);
                NSMutableData *wadoUrisData=[NSMutableData data];
                int studiesResult=task(@"/bin/bash",
                                       @[@"-s"],
                                       [WadoUrisSqlString dataUsingEncoding:NSUTF8StringEncoding],
                                       wadoUrisData
                                       );
                __block NSMutableArray *wados=[NSJSONSerialization JSONObjectWithData:wadoUrisData options:NSJSONReadingMutableContainers error:nil];
                __block NSMutableData *directory=[NSMutableData data];
                __block uint32 entryPointer=0;
                __block uint16 entriesCount=0;

                 // The RSAsyncStreamBlock works like the RSStreamBlock
                 // The block must call "completionBlock" passing the new chunk of data when ready, an empty NSData when done, or nil on error and pass a NSError.
                 // The block cannot call "completionBlock" more than once per invocation.
                RSStreamedResponse* response = [RSStreamedResponse responseWithContentType:@"application/octet-stream" asyncStreamBlock:^(RSBodyReaderCompletionBlock completionBlock)
                {
                if (wados.count>0)
                {
                    //request, response and error
                    NSString *wadoString=[NSString stringWithFormat:@"%@%@%@",
                                          destPacs[@"wadouri"],
                                          wados[0],
                                          destPacs[@"wadoadditionalparameters"]];
                    __block NSData *wadoData=[NSData dataWithContentsOfURL:[NSURL URLWithString:wadoString]];
                    if (!wadoData)
                    {
                        NSLog(@"could not retrive: %@",wadoString);
                        completionBlock([NSData data], nil);
                    }
                    else
                    {
                        [wados removeObjectAtIndex:0];
                        unsigned long wadoLength=(unsigned long)[wadoData length];
                        NSString *dcmUUID=[[[NSUUID UUID]UUIDString]stringByAppendingPathExtension:@"dcm"];
                        NSData *dcmName=[dcmUUID dataUsingEncoding:NSUTF8StringEncoding];
                        //LOG_INFO(@"dcm (%lu bytes):%@",dcmLength,dcmUUID);
                    
                        __block NSMutableData *entry=[NSMutableData data];
                        [entry appendBytes:&zipLocalFileHeader length:4];//0x04034B50
                        [entry appendBytes:&zipVersion length:2];//0x000A
                        [entry increaseLengthBy:8];//uint32 flagCompression,zipTimeDate
                        uint32 zipCrc32=[wadoData crc32];
                        [entry appendBytes:&zipCrc32 length:4];
                        [entry appendBytes:&wadoLength length:4];//zipCompressedSize
                        [entry appendBytes:&wadoLength length:4];//zipUncompressedSize
                        [entry appendBytes:&zipNameLength length:4];//0x28
                        [entry appendData:dcmName];
                        //extra param
                        [entry appendData:wadoData];
                    
                        completionBlock(entry, nil);
                        
                        //directory
                        [directory appendBytes:&zipFileHeader length:4];//0x02014B50
                        [directory appendBytes:&zipVersion length:2];//0x000A
                        [directory appendBytes:&zipVersion length:2];//0x000A
                        [directory increaseLengthBy:8];//uint32 flagCompression,zipTimeDate
                        [directory appendBytes:&zipCrc32 length:4];
                        [directory appendBytes:&wadoLength length:4];//zipCompressedSize
                        [directory appendBytes:&wadoLength length:4];//zipUncompressedSize
                        [directory appendBytes:&zipNameLength length:4];//0x28
                        /*
                         uint16 zipFileCommLength=0x0;
                         uint16 zipDiskStart=0x0;
                         uint16 zipInternalAttr=0x0;
                         uint32 zipExternalAttr=0x0;
                         */
                        [directory increaseLengthBy:10];
                        
                        [directory appendBytes:&entryPointer length:4];//offsetOfLocalHeader
                        entryPointer+=wadoLength+70;
                        entriesCount++;
                        [directory appendData:dcmName];
                        //extra param
                    }
                }
                else if (directory.length) //chunk with directory
                {
                    //ZIP "end of central directory record"
                
                    //uint32 zipEndOfCentralDirectory=0x06054B50;
                    [directory appendBytes:&zipEndOfCentralDirectory length:4];
                    [directory increaseLengthBy:4];//zipDiskNumber
                    [directory appendBytes:&entriesCount length:2];//disk zipEntries
                    [directory appendBytes:&entriesCount length:2];//total zipEntries
                    uint32 directorySize=86 * entriesCount;
                    [directory appendBytes:&directorySize length:4];
                    [directory appendBytes:&entryPointer length:4];
                    [directory increaseLengthBy:2];//zipCommentLength
                    completionBlock(directory, nil);
                    [directory setData:[NSData data]];
                }
                else completionBlock([NSData data], nil);//last chunck
                
            }];

            return response;
            
            }
            else
            {
                //series wadors
                NSArray *seriesArray=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/series?%@",destPacs[@"qido"],request.URL.query]]] options:0 error:nil];

                
                __block NSMutableArray *wados=[NSMutableArray array];
                for (NSDictionary *dictionary in seriesArray)
                {
                    //download series
                    //00081190 UR RetrieveURL
                    [wados addObject:((dictionary[@"00081190"])[@"Value"])[0]];
    #pragma mark TODO correct proxy wadors...
                }
                LOG_DEBUG(@"%@",[wados description]);

                
                __block NSMutableData *wadors=[NSMutableData data];
                __block NSMutableData *boundary=[NSMutableData data];
                __block NSMutableData *directory=[NSMutableData data];
                __block NSRange wadorsRange=NSMakeRange(0,0);
                __block uint32 entryPointer=0;
                __block uint16 entriesCount=0;
                __block NSRange ctadRange=NSMakeRange(0,0);
                __block NSRange boundaryRange=NSMakeRange(0,0);

                /**
                 *  The RSAsyncStreamBlock works like the RSStreamBlock
                 *  except the streamed data can be returned at a later time allowing for
                 *  truly asynchronous generation of the data.
                 *
                 *  The block must call "completionBlock" passing the new chunk of data when ready,
                 *  an empty NSData when done, or nil on error and pass a NSError.
                 *
                 *  The block cannot call "completionBlock" more than once per invocation.
                 */
                
                RSStreamedResponse* response = [RSStreamedResponse responseWithContentType:@"application/octet-stream" asyncStreamBlock:^(RSBodyReaderCompletionBlock completionBlock)
                {
                    if (wadorsRange.length<1000)
                    {
                        LOG_INFO(@"need data. Remaining wadors:%lu",(unsigned long)wados.count);
                        if (wados.count>0)
                        {
                            //request, response and error
                            NSMutableURLRequest *wadorsRequest=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:wados[0]] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:timeout];
                            //https://developer.apple.com/reference/foundation/nsurlrequestcachepolicy?language=objc
                            //NSURLRequestReloadIgnoringCacheData
                            [wadorsRequest setHTTPMethod:@"GET"];
                            [wadorsRequest setValue:@"multipart/related;type=application/dicom" forHTTPHeaderField:@"Accept"];
                            NSHTTPURLResponse *response=nil;
                            //URL properties: expectedContentLength, MIMEType, textEncodingName
                            //HTTP properties: statusCode, allHeaderFields
                            
                            NSError *error=nil;
                            [wadors setData:[NSURLConnection sendSynchronousRequest:wadorsRequest returningResponse:&response error:&error]];
                            if (response.statusCode==200)
                            {
                                wadorsRange.location=0;
                                wadorsRange.length=[wadors length];
                                NSString *ctString=response.allHeaderFields[@"Content-Type"];
                                NSString *boundaryString=[@"\r\n--" stringByAppendingString:[ctString substringFromIndex:ctString.length-36]];
                                [boundary setData:[boundaryString dataUsingEncoding:NSUTF8StringEncoding]];
                                LOG_INFO(@"%@\r\n(%lu,%lu) boundary:%@",wados[0],(unsigned long)wadorsRange.location,(unsigned long)wadorsRange.length,boundaryString);
                            }
                            [wados removeObjectAtIndex:0];
                        }
                    }
                    ctadRange=[wadors rangeOfData:ctad options:0 range:wadorsRange];
                    boundaryRange=[wadors rangeOfData:boundary options:0 range:wadorsRange];
                    if ((ctadRange.length>0) && (boundaryRange.length>0)) //chunk with new entry
                    {
                        //dcm
                        unsigned long dcmLocation=ctadRange.location+ctadRange.length;
                        unsigned long dcmLength=boundaryRange.location-dcmLocation;
                        wadorsRange.location=boundaryRange.location+boundaryRange.length;
                        wadorsRange.length=wadors.length-wadorsRange.location;
                        
                        NSString *dcmUUID=[[[NSUUID UUID]UUIDString]stringByAppendingPathExtension:@"dcm"];
                        NSData *dcmName=[dcmUUID dataUsingEncoding:NSUTF8StringEncoding];
                        //LOG_INFO(@"dcm (%lu bytes):%@",dcmLength,dcmUUID);
                        
                        __block NSMutableData *entry=[NSMutableData data];
                        [entry appendBytes:&zipLocalFileHeader length:4];//0x04034B50
                        [entry appendBytes:&zipVersion length:2];//0x000A
                        [entry increaseLengthBy:8];//uint32 flagCompression,zipTimeDate
                        
                        NSData *dcmData=[wadors subdataWithRange:NSMakeRange(dcmLocation,dcmLength)];
                        uint32 zipCrc32=[dcmData crc32];
                        
                        [entry appendBytes:&zipCrc32 length:4];
                        [entry appendBytes:&dcmLength length:4];//zipCompressedSize
                        [entry appendBytes:&dcmLength length:4];//zipUncompressedSize
                        [entry appendBytes:&zipNameLength length:4];//0x28
                        [entry appendData:dcmName];
                        //extra param
                        [entry appendData:dcmData];
                        
                        completionBlock(entry, nil);
                        
                        //directory
                        [directory appendBytes:&zipFileHeader length:4];//0x02014B50
                        [directory appendBytes:&zipVersion length:2];//0x000A
                        [directory appendBytes:&zipVersion length:2];//0x000A
                        [directory increaseLengthBy:8];//uint32 flagCompression,zipTimeDate
                        [directory appendBytes:&zipCrc32 length:4];
                        [directory appendBytes:&dcmLength length:4];//zipCompressedSize
                        [directory appendBytes:&dcmLength length:4];//zipUncompressedSize
                        [directory appendBytes:&zipNameLength length:4];//0x28
                        /*
                         uint16 zipFileCommLength=0x0;
                         uint16 zipDiskStart=0x0;
                         uint16 zipInternalAttr=0x0;
                         uint32 zipExternalAttr=0x0;
                         */
                        [directory increaseLengthBy:10];
                        
                        [directory appendBytes:&entryPointer length:4];//offsetOfLocalHeader
                        entryPointer+=dcmLength+70;
                        entriesCount++;
                        [directory appendData:dcmName];
                        //extra param
                    }
                    else if (directory.length) //chunk with directory
                    {
                        //ZIP "end of central directory record"
                        
                        //uint32 zipEndOfCentralDirectory=0x06054B50;
                        [directory appendBytes:&zipEndOfCentralDirectory length:4];
                        [directory increaseLengthBy:4];//zipDiskNumber
                        [directory appendBytes:&entriesCount length:2];//disk zipEntries
                        [directory appendBytes:&entriesCount length:2];//total zipEntries
                        uint32 directorySize=86 * entriesCount;
                        [directory appendBytes:&directorySize length:4];
                        [directory appendBytes:&entryPointer length:4];
                        [directory increaseLengthBy:2];//zipCommentLength
                        completionBlock(directory, nil);
                        [directory setData:[NSData data]];
                    }
                    else completionBlock([NSData data], nil);//last chunck
                    
                }];

                return response;
            }
            
        }(request));}];

        

        
#pragma mark ot  doc  cda
        /*
        {proxy}/ot?
        {proxy}/doc?
        {proxy}/cda?
         */
        NSRegularExpression *encapsulatedRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/pacs\\/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*\\/(ot|doc|cda)$" options:NSRegularExpressionCaseInsensitive error:NULL];
         [httpdicomServer addHandler:@"GET" regex:encapsulatedRegex processBlock:
          ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];

             NSDictionary *destPacs=pacsDictionaries[pComponents[2]];
             if (!destPacs) return [RSErrorResponse responseWithClientError:404 message:@"%@ [{pacs} not found]",request.path];
             
             //buscar SERIES wadors URIs
             if (!destPacs[@"qido"]) return [RSErrorResponse responseWithClientError:404 message:@"%@ [qido not available]",request.path];

             //AccessionNumber
             NSString *q=request.URL.query;
             if (q.length>32 || ![q hasPrefix:@"AccessionNumber="]) [RSErrorResponse responseWithClientError:404 message:@"%@ [lacks parameter AccessionNumber]",request.path];
             NSString *accessionNumber=[q substringWithRange:NSMakeRange(16,q.length-16)];
             
             NSString *modality;
                  if ([pComponents[3] isEqualToString:@"doc"]) modality=@"DOC";
             else if ([pComponents[3] isEqualToString:@"cda"]) modality=@"DOC";
             else if ([pComponents[3] isEqualToString:@"ot"]) modality=@"OT";
             
             //instances?AccessionNumber={AccessionNumber}&Modality=DOC
             NSString *qidoString=[NSString stringWithFormat:@"%@/instances?AccessionNumber=%@&Modality=%@",
                                destPacs[@"qido"],
                                accessionNumber,
                                modality];
             LOG_DEBUG(@"%@/r/n->%@",request.path,qidoString);
             NSData *instanceQidoData=[NSData dataWithContentsOfURL:
                                   [NSURL URLWithString:qidoString]];

             
             //applicable, latest doc
             //6.7.1.2.3.2 JSON Results
             //If there are no matching results,the JSON message is empty.
             if (!instanceQidoData || ![instanceQidoData length]) [RSErrorResponse responseWithClientError:404 message:@"%@ [not found]",request.path];
             
             NSArray *instanceArray=[NSJSONSerialization JSONObjectWithData:instanceQidoData options:0 error:nil];
             NSUInteger instanceArrayCount=[instanceArray count];
             if (instanceArrayCount==0) [RSErrorResponse responseWithClientError:404 message:@"dev0 /applicable not found"];//NotFound
             
             NSDictionary *instance;
             NSInteger i=0;
             NSInteger index=0;
             NSInteger date=0;
             NSInteger time=0;
             if (instanceArrayCount==1) instance=instanceArray[0];
             else
             {
                 for (i=0;  i<instanceArrayCount; i++)
                 {
                     NSInteger PPSSD=[(((instanceArray[i])[@"00400244"])[@"Value"])[0] longValue];
                     NSInteger PPSST=[(((instanceArray[i])[@"00400245"])[@"Value"])[0] longValue];
                     if ((PPSSD > date) || ((PPSSD==date)&&(PPSST>time)))
                     {
                         date=PPSSD;
                         time=PPSST;
                         index=i;
                     }
                 }
                 instance=instanceArray[index];
             }

             //wadors returns bytstream with 00420010
             NSString *wadoRsString=(((instanceArray[index])[@"00081190"])[@"Value"])[0];
             LOG_INFO(@"applicable wadors %@",wadoRsString);
             
             NSData *applicableData=[NSData dataWithContentsOfURL:[NSURL URLWithString:wadoRsString]];
             if (!applicableData || ![applicableData length]) return [RSErrorResponse responseWithClientError:404 message:@"applicable %@ notFound",request.URL.path];

             NSUInteger applicableDataLength=[applicableData length];

             NSUInteger valueLocation;
             //between "Content-Type: " and "\r\n"
             NSRange ctRange  = [applicableData rangeOfData:contentType options:0 range:NSMakeRange(0, applicableDataLength)];
             valueLocation=ctRange.location+ctRange.length;
             NSRange rnRange  = [applicableData rangeOfData:rn options:0 range:NSMakeRange(valueLocation, applicableDataLength-valueLocation)];
             NSData *contentTypeData=[applicableData subdataWithRange:NSMakeRange(valueLocation,rnRange.location-valueLocation)];
             NSString *ctString=[[NSString alloc]initWithData:contentTypeData encoding:NSUTF8StringEncoding];
             LOG_INFO(@"%@",ctString);

             
             //between "\r\n\r\n" and "\r\n--"
             NSRange rnrnRange=[applicableData rangeOfData:rnrn options:0 range:NSMakeRange(0, applicableDataLength)];
             valueLocation=rnrnRange.location+rnrnRange.length;
             NSRange rnhhRange=[applicableData rangeOfData:rnhh options:0 range:NSMakeRange(valueLocation, applicableDataLength-valueLocation)];
             
             //encapsulatedData
             NSData *encapsulatedData=[applicableData subdataWithRange:NSMakeRange(valueLocation,rnhhRange.location-valueLocation - 1 - ([[applicableData subdataWithRange:NSMakeRange(rnhhRange.location-2,2)] isEqualToData:rn] * 2))];
                 
             if ([modality isEqualToString:@"CDA"])
             {
                 LOG_INFO(@"CDA");
                 NSRange CDAOpeningTagRange=[encapsulatedData rangeOfData:CDAOpeningTag options:0 range:NSMakeRange(0, encapsulatedData.length)];
                 if (CDAOpeningTagRange.location != NSNotFound)
                 {
                     NSRange CDAClosingTagRange=[encapsulatedData rangeOfData:CDAClosingTag options:0 range:NSMakeRange(0, encapsulatedData.length)];
                     NSData *cdaData=[encapsulatedData subdataWithRange:NSMakeRange(CDAOpeningTagRange.location, CDAClosingTagRange.location+CDAClosingTagRange.length-CDAOpeningTagRange.location)];
                     return [RSDataResponse
                             responseWithData:cdaData
                             contentType:ctString];
                 }
             }
             
             return [RSDataResponse
                    responseWithData:encapsulatedData
                    contentType:ctString];
             
         }(request));}];

        
        
#pragma mark /manifest/weasis/studies?
        NSRegularExpression *mwstudiesRegex = [NSRegularExpression regularExpressionWithPattern:@"^/manifest/weasis/studies" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandler:@"GET" regex:mwstudiesRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock)
         {completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];
             
             //request parts logging
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             //NSString *q=requestURL.query;
             NSDictionary *q=request.query;


             NSDictionary *destPacs=pacsDictionaries[q[@"custodianOID"]];
             NSDictionary *destSql=sql[destPacs[@"sqlQueriesDictionary"]];
             if (!destSql) return [RSErrorResponse responseWithClientError:404 message:@"%@ [sql not found]",request.path];

             NSString *sqlString;
             NSString *AccessionNumber=request.query[@"AccessionNumber"];
             if (AccessionNumber)sqlString=[NSString stringWithFormat:destSql[@"manifestWeasisStudyAccessionNumber"],AccessionNumber];
             else
             {
                 NSString *StudyInstanceUID=request.query[@"StudyInstanceUID"];
                 if (StudyInstanceUID)sqlString=[NSString stringWithFormat:destSql[@"manifestWeasisStudyStudyInstanceUID"],StudyInstanceUID];
                 else return [RSErrorResponse responseWithClientError:404 message:
                              @"parameter AccessionNumber or StudyInstanceUID required in %@%@?%@",b,p,q];
             }
             //SQL for studies
             NSMutableData *studiesData=[NSMutableData data];
             int studiesResult=task(@"/bin/bash",
                                    @[@"-s"],
                                    [sqlString dataUsingEncoding:NSUTF8StringEncoding],
                                    studiesData
                                    );
             NSMutableArray *studyArray=[NSJSONSerialization JSONObjectWithData:studiesData options:0 error:nil];
            /*
                [0]  p.family_name,p.given_name,p.middle_name,p.name_prefix,p.name_suffix,
                [1] patient_id.pat_id,
                [2] iopid.entity_uid,
                [3] patient.pat_birthdate,
                [4] patient.pat_sex,
             
                [5] study.study_iuid,
                [6] study.accession_no,
                [7] ioan.entity_uid,
                [8] study_query_attrs.retrieve_aets,
                [9] study.study_id,
                [10] study.study_desc,
                [11] study.study_date,
                [12] study.study_time
                [13] NumberOfStudyRelatedInstances
             */
             //the accessionNumber may join more than one study of one or more patient !!!
             //look for patient roots first
             NSMutableArray *uniquePatients=[NSMutableArray array];
             for (NSArray *studyInstance in studyArray)
             {
                 [uniquePatients addObject:[studyInstance[1]stringByAppendingPathComponent:studyInstance[2]]];
             }
             
             NSMutableString *weasisManifest=[NSMutableString string];
             //each patient
                 for (NSString *patient in [NSSet setWithArray:uniquePatients])
                 {
                     NSUInteger studyIndex=[uniquePatients indexOfObject:patient];
                     NSArray *patientAttrs=studyArray[studyIndex];
                     [weasisManifest appendFormat:
                      @"<Patient PatientName=\"%@\" PatientID=\"%@\" IssuerOfPatientID=\"%@\" PatientBirthDate=\"%@\" PatientSex=\"%@\">\r",
                      patientAttrs[0],
                      patientAttrs[1],
                      patientAttrs[2],
                      patientAttrs[3],
                      patientAttrs[4]
                      ];
                     
                     for (NSArray *studyInstance in studyArray)
                     {
                         if (  [studyInstance[1]isEqualToString:patientAttrs[1]]
                             &&[studyInstance[2]isEqualToString:patientAttrs[2]]
                            )
                         {
                            //each study of this patient
                             [weasisManifest appendFormat:
                              @"<Study SpecificCharacterSet=\"UTF-8\" StudyInstanceUID=\"%@\" AccessionNumber=\"%@\" IssuerOfAccessionNumber=\"%@\" RetrieveAETitle=\"%@\" StudyID=\"%@\" StudyDescription=\"%@\" StudyDate=\"%@\" StudyTime=\"%@\" WadorsURI=\"/studies/%@\" NumberOfStudyRelatedInstances=\"%@\">\r",
                              studyInstance[5],
                              studyInstance[6],
                              studyInstance[7],
                              studyInstance[8],
                              studyInstance[9],
                              studyInstance[10],
                              studyInstance[11],
                              studyInstance[12],
                              studyInstance[5],
                              studyInstance[13]
                              ];
                             
                             //series

                             NSMutableData *seriesData=[NSMutableData data];
                             int seriesResult=task(@"/bin/bash",
                                                    @[@"-s"],
                                                    [[NSString stringWithFormat:destSql[@"manifestWeasisSeriesStudyInstanceUID"],studyInstance[5]]
                                                     dataUsingEncoding:NSUTF8StringEncoding],
                                                    seriesData
                                                    );
                             NSMutableArray *seriesArray=[NSJSONSerialization JSONObjectWithData:seriesData options:0 error:nil];
                             for (NSArray *seriesInstance in seriesArray)
                             {
                                 [weasisManifest appendFormat:
                                  @"<Series SeriesInstanceUID=\"%@\" SeriesDescription=\"%@\" SeriesNumber=\"%@\" Modality=\"%@\"  WadorsURI=\"/studies/%@/series/%@\" NumberOfSeriesRelatedInstances=\"%@\">\r",
                                  seriesInstance[0],
                                  seriesInstance[1],
                                  seriesInstance[2],
                                  seriesInstance[3],
                                  studyInstance[5],
                                  seriesInstance[0],
                                  seriesInstance[4]
                                  ];
                                 //instances
                                 NSMutableData *instanceData=[NSMutableData data];
                                 int instanceResult=task(@"/bin/bash",
                                                       @[@"-s"],
                                                       [[NSString stringWithFormat:destSql[@"manifestWeasisInstanceSeriesInstanceUID"],seriesInstance[0]]
                                                        dataUsingEncoding:NSUTF8StringEncoding],
                                                       instanceData
                                                       );
                                 NSMutableArray *instanceArray=[NSJSONSerialization JSONObjectWithData:instanceData options:0 error:nil];
                                 for (NSArray *instance in instanceArray)
                                 {
                                     [weasisManifest appendFormat:
                                      @"<Instance SOPInstanceUID=\"%@\" InstanceNumber=\"%@\" SOPClassUID=\"%@\"/>\r",
                                      instance[0],
                                      instance[1],
                                      instance[2]
                                      ];
                                 }
                                 [weasisManifest appendString:@"</Series>\r"];
                             }
                             [weasisManifest appendString:@"</Study>\r"];
                         }
                     }
                     [weasisManifest appendString:@"</Patient>\r"];
                 }
                 return [RSDataResponse responseWithData:[weasisManifest dataUsingEncoding:NSUTF8StringEncoding] contentType:@"text/xml"];
             
         }(request));}];
        
        
#pragma mark /manifest/weasis/studies/{StudyInstanceUID}/series/{SeriesInstanceUID}
        NSRegularExpression *mwseriesRegex = [NSRegularExpression regularExpressionWithPattern:@"^/manifest/weasis/studies/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*/series/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandler:@"GET" regex:mwseriesRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock)
         {completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];

             //request parts logging
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             
             NSString *p=requestURL.path;
             NSString *StudyInstanceUID=pComponents[4];
             NSString *SeriesInstanceUID=pComponents[6];
             
             //NSString *q=requestURL.query;
             NSDictionary *q=request.query;
             NSDictionary *destPacs=pacsDictionaries[q[@"custodianOID"]];
             NSDictionary *destSql=sql[destPacs[@"sqlQueriesDictionary"]];
             if (!destSql) return [RSErrorResponse responseWithClientError:404 message:@"%@ [sql not found]",request.path];

             NSString *sqlString=[NSString stringWithFormat:destSql[@"manifestWeasisSeriesStudyInstanceUIDSeriesInstanceUID"],StudyInstanceUID,SeriesInstanceUID];
 
             //LOG_INFO(@"%@",sqlString);
            
             //SQL for series
             NSMutableData *seriesData=[NSMutableData data];
             int seriesResult=task(@"/bin/bash",
                                    @[@"-s"],
                                    [sqlString dataUsingEncoding:NSUTF8StringEncoding],
                                    seriesData
                                    );
             NSMutableArray *seriesArray=[NSJSONSerialization JSONObjectWithData:seriesData options:0 error:nil];
             if (![seriesArray count]) return [RSErrorResponse responseWithClientError:404 message:@"0 record for %@%@?%@",b,p,q];
             /*
              [0] SeriesInstanceUID,
              [1] SeriesDescription,
              [2] SeriesNumber,
              [3] Modality,
              */
             
             //get corresponding patient and study
             //SQL for studies

             NSMutableData *studiesData=[NSMutableData data];
             int studiesResult=task(@"/bin/bash",
                                    @[@"-s"],
                                    [[NSString stringWithFormat:destSql[@"manifestWeasisStudyStudyInstanceUID"],StudyInstanceUID] dataUsingEncoding:NSUTF8StringEncoding],
                                    studiesData
                                    );
             NSMutableArray *studyArray=[NSJSONSerialization JSONObjectWithData:studiesData options:0 error:nil];
             /*
              [0]  p.family_name,p.given_name,p.middle_name,p.name_prefix,p.name_suffix,
              [1] patient_id.pat_id,
              [2] iopid.entity_uid,
              [3] patient.pat_birthdate,
              [4] patient.pat_sex,
              
              [5] study.study_iuid,
              [6] study.accession_no,
              [7] ioan.entity_uid,
              [8] study_query_attrs.retrieve_aets,
              [9] study.study_id,
              [10] study.study_desc,
              [11] study.study_date,
              [12] study.study_time
              */
             //the accessionNumber may join more than one study of one or more patient !!!
             //look for patient roots first
             NSMutableArray *uniquePatients=[NSMutableArray array];
             for (NSArray *studyInstance in studyArray)
             {
                 [uniquePatients addObject:[studyInstance[1]stringByAppendingPathComponent:studyInstance[2]]];
             }
             
             NSMutableString *weasisManifest=[NSMutableString string];
             //each patient
             for (NSString *patient in [NSSet setWithArray:uniquePatients])
             {
                 NSUInteger studyIndex=[uniquePatients indexOfObject:patient];
                 NSArray *patientAttrs=studyArray[studyIndex];
                 [weasisManifest appendFormat:
                  @"<Patient PatientName=\"%@\" PatientID=\"%@\" IssuerOfPatientID=\"%@\" PatientBirthDate=\"%@\" PatientSex=\"%@\">\r",
                  patientAttrs[0],
                  patientAttrs[1],
                  patientAttrs[2],
                  patientAttrs[3],
                  patientAttrs[4]
                  ];
                 
                 for (NSArray *studyInstance in studyArray)
                 {
                     if (  [studyInstance[1]isEqualToString:patientAttrs[1]]
                         &&[studyInstance[2]isEqualToString:patientAttrs[2]]
                         )
                     {
                         //each study of this patient
                         [weasisManifest appendFormat:
                          @"<Study SpecificCharacterSet=\"UTF-8\" StudyInstanceUID=\"%@\" AccessionNumber=\"%@\" IssuerOfAccessionNumber=\"%@\" RetrieveAETitle=\"%@\" StudyID=\"%@\" StudyDescription=\"%@\" StudyDate=\"%@\" StudyTime=\"%@\" WadorsURI=\"/studies/%@\" NumberOfStudyRelatedInstances=\"%@\">\r",
                          studyInstance[5],
                          studyInstance[6],
                          studyInstance[7],
                          studyInstance[8],
                          studyInstance[9],
                          studyInstance[10],
                          studyInstance[11],
                          studyInstance[12],
                          studyInstance[5],
                          studyInstance[13]
                          ];
                         for (NSArray *seriesInstance in seriesArray)
                         {
                             [weasisManifest appendFormat:
                              @"<Series SeriesInstanceUID=\"%@\" SeriesDescription=\"%@\" SeriesNumber=\"%@\" Modality=\"%@\"  WadorsURI=\"/studies/%@/series/%@\" NumberOfSeriesRelatedInstances=\"%@\">\r",
                              seriesInstance[0],
                              seriesInstance[1],
                              seriesInstance[2],
                              seriesInstance[3],
                              studyInstance[5],
                              seriesInstance[0],
                              seriesInstance[4]
                              ];
                             
                             //instances
                             NSMutableData *instanceData=[NSMutableData data];
                             int instanceResult=task(@"/bin/bash",
                                                     @[@"-s"],
                                                     [[NSString stringWithFormat:destSql[@"manifestWeasisInstanceSeriesInstanceUID"],seriesInstance[0]]
                                                      dataUsingEncoding:NSUTF8StringEncoding],
                                                     instanceData
                                                     );
                             NSMutableArray *instanceArray=[NSJSONSerialization JSONObjectWithData:instanceData options:0 error:nil];
                             for (NSArray *instance in instanceArray)
                             {
                                 [weasisManifest appendFormat:
                                  @"<Instance SOPInstanceUID=\"%@\" InstanceNumber=\"%@\" SOPClassUID=\"%@\"/>\r",
                                  instance[0],
                                  instance[1],
                                  instance[2]
                                  ];
                             }
                             [weasisManifest appendString:@"</Series>\r"];
                         }
                         [weasisManifest appendString:@"</Study>\r"];
                     }
                 }
                 [weasisManifest appendString:@"</Patient>\r"];
             }
             return [RSDataResponse responseWithData:[weasisManifest dataUsingEncoding:NSUTF8StringEncoding] contentType:@"application/json"];
             
         }(request));}];
        
        
#pragma mark patient
        /*
         patient?{PatientID, IssuerOfPatientID, PatientName(family^given^middle^prefix^suffix), PatientBirthDate, PatientSex} [&pacs="oid" [...]]
         -> array of object patient (which include pacs, issuer data table patient, first and last study, number of studies, modalities found)
         */
        NSRegularExpression *patientRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\/patient$" options:NSRegularExpressionCaseInsensitive error:NULL];
         [httpdicomServer addHandler:@"GET" regex:patientRegex processBlock:
          ^(RSRequest* request, RSCompletionBlock completionBlock)
          {completionBlock(^RSResponse* (RSRequest* request)
          {
              LOG_DEBUG(@"client: %@",request.remoteAddressString);
              //using NSURLComponents instead of RSRequest
              NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];

              //get query part
                 NSArray *queryItems=[urlComponents queryItems];
                 
                 //filter queryItems to find the once with name pacs
                 //create duplicate of pacs array or subselection of it based on selection(eventually multiple
                 NSMutableArray *pacsOidsQueried = [NSMutableArray array];
                 NSMutableDictionary *otherQueryItems = [NSMutableDictionary dictionary];
                 NSMutableSet *sqlConnectionSet = [NSMutableSet set];
                 BOOL hasPacsQueryItem=false;
                 BOOL hasPatientID=false;
                 BOOL hasIssuerOfPatientID=false;
                 BOOL hasPatientName=false;
                 BOOL hasPatientBirthDate=false;
                 BOOL hasPatientSex=false;
                 NSLog(@"queryItems: %@",[queryItems description]);
             
                 for (NSURLQueryItem *qi in queryItems) {
                     NSString *qin=qi.name;
                     if ([qin isEqualToString:@"pacs"])
                     {
                         hasPacsQueryItem=true;
                         NSString *sqlConnection=(pacsDictionaries[qi.value])[sql];
                         if ([pacsOids containsObject:qi.value] && ![sqlConnection isEqualToString:@""])
                         {
                             [pacsOidsQueried addObject:qi.value];
                             [sqlConnectionSet addObject:sqlConnection];
                         }
                     }
                     else if (!hasPatientID && [qin isEqualToString:@"PatientID"])
                     {
                         [otherQueryItems setObject:qi.value forKey:qin];
                         hasPatientID=true;
                     }
                     else if (!hasIssuerOfPatientID && [qin isEqualToString:@"IssuerOfPatientID"])
                     {
                         [otherQueryItems setObject:qi.value forKey:qin];
                         hasIssuerOfPatientID=true;
                     }
                     else if (!hasPatientName && [qin isEqualToString:@"PatientName"])
                     {
                         [otherQueryItems setObject:qi.value forKey:qin];
                         hasPatientName=true;
                     }
                     else if (!hasPatientBirthDate && [qin isEqualToString:@"PatientBirthDate"])
                     {
                         [otherQueryItems setObject:qi.value forKey:qin];
                         hasPatientBirthDate=true;
                     }
                     else if (!hasPatientSex && [qin isEqualToString:@"PatientSex"])
                     {
                         [otherQueryItems setObject:qi.value forKey:qin];
                         hasPatientSex=true;
                     }
                 }
                 //if no specific then all
                 if (!hasPacsQueryItem) [pacsOidsQueried addObjectsFromArray:pacsOids];
                 
                 //error if bad pacs query item
                 if ([pacsOids count]==0)   return [RSErrorResponse responseWithClientError:404 message:@"%@ [/patient? requires a valid pacs queryItem or no pacs queryItem to propagate the query to all the known pacs]",request.path];
                 
                 //error if no patient query item
                 if ([otherQueryItems count]==0)  return [RSErrorResponse responseWithClientError:404 message:@"%@ [/patient? requires at least one filter]",request.path];
                 
                 NSMutableDictionary *sqlsPatient = [NSMutableDictionary dictionary];
                 NSMutableDictionary *sqlsStudy = [NSMutableDictionary dictionary];
                 for (NSString *sqlConnectionPath in sqlConnectionSet)
                 {
                     NSDictionary *sqlDict = sql[sqlConnectionPath];
                     //create sql patient query based on otherQueryItems
                     NSMutableString *patientWhere=[NSMutableString stringWithString:sqlDict[@"patientWhere"]];
                     if (hasPatientID)
                         [patientWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                           fieldString:sqlDict[@"PatientID"]
                                           valueString:otherQueryItems[@"PatientID"]
                           ]
                          ];
                     if (hasIssuerOfPatientID)
                         [patientWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                           fieldString:sqlDict[@"IssuerOfPatientID"]
                                           valueString:otherQueryItems[@"IssuerOfPatientID"]
                           ]
                          ];
                     //for now, only first name
                     if (hasPatientName)
                         [patientWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                           fieldString:(sqlDict[@"PatientName"])[0]
                                           valueString:otherQueryItems[@"PatientName"]
                           ]
                          ];
                     if (hasPatientBirthDate)
                         [patientWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                           fieldString:sqlDict[@"PatientBirthDate"]
                                           valueString:otherQueryItems[@"PatientBirthDate"]
                           ]
                          ];
                     if (hasPatientSex)
                         [patientWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                           fieldString:sqlDict[@"PatientSex"]
                                           valueString:otherQueryItems[@"PatientSex"]
                           ]
                          ];
                     
                     LOG_INFO(@"WHERE %@",patientWhere);
                 }
                     /*
                     
                     NSString *sqlDataQuery=
                     [[sqlDict[@"patientProlog"]
                       stringByAppendingString:patientWhere]
                      stringByAppendingFormat:sqlDict[@"patientEpilog"],session,session];
                     
                     NSMutableArray *studiesArray=jsonMutableArray(sqlDataQuery, [destPacs[@"sqlStringEncoding"]unsignedIntegerValue]);
                     
                     //sorted study date (5) desc
                     [studiesArray sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                         return [obj2[5] caseInsensitiveCompare:obj1[5]];
                     }];
                     
                     
                     //create sql study based on pk patient
                 }
                 //apply to pacs patient sql and for each result the corresponding sql query and for any merge the corresponding sql study. Keep the results in a big json
                 for (NSString *pacsOid in pacsOids)
                 {
                     
                 }
                 
                 
                 //reply
                 NSArray *pComponents=[request.path componentsSeparatedByString:@"/"];
                 NSDictionary *pacsaei=pacsDictionaries[pComponents[2]];
                 if (!pacsaei) return [RSErrorResponse responseWithClientError:404 message:@"%@ [{pacs} not found]",request.path];
                 
                 NSString *pcsuri=pacsaei[@"pcsuri"];
                 
                 NSString *q=request.URL.query;//a same param may repeat
                 
                 NSString *qidoBaseString=pacsaei[@"qido"];
                 if (![qidoBaseString isEqualToString:@""])
                 {
                     return qidoUrlProxy(
                                         [NSString stringWithFormat:@"%@/%@",qidoBaseString,pComponents.lastObject],
                                         q,
                                         [pcsuri stringByAppendingString:request.path]
                                         );//application/dicom+json not accepted
                 }
                 
                 NSString *sql=pacsaei[@"sqlQueriesDictionary"];
                 if (sql)
                 {
                     //local ... simulation qido through database access
#pragma mark TODO QIDO SQL
                 }
                 
                 if (pcsuri)
                 {
                     //remote... access through another PCS
                     NSString *urlString;
                     if (q) urlString=[NSString stringWithFormat:@"%@/%@?%@",
                                       pcsuri,
                                       request.path,
                                       q];
                     else    urlString=[NSString stringWithFormat:@"%@/%@?",
                                        pcsuri,
                                        request.path];
                     LOG_INFO(@"[QIDO] %@",urlString);
                     return urlProxy(urlString,@"application/dicom+json");
                 }
                 
                 
                 return [RSErrorResponse responseWithClientError:404 message:@"%@ [QIDO not available]",request.path];
             */
             
             
             //mockup return
             return [RSDataResponse responseWithText:[NSString stringWithFormat:@"user IP:port [%@]",request.remoteAddressString]];

         }(request));}];

#pragma mark datatables/studies
        /*
         query ajax with params:
         agregate 00080090 in other accesible PCS...
         
         q=current query
         r=Req=request sql
         s=subselection from caché
         */
        NSRegularExpression *dtstudiesRegex = [NSRegularExpression regularExpressionWithPattern:@"/datatables/studies" options:0 error:NULL];
        [httpdicomServer addHandler:@"GET" regex:dtstudiesRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_VERBOSE(@"%@",[request.URL description]);
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];
             

             NSDictionary *q=request.query;
             
             NSString *session=q[@"session"];
             if (!session || [session isEqualToString:@""]) return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'session' parameter"] contentType:@"application/dicom+json"];
             
             NSDictionary *r=Req[session];
             int recordsTotal;
             
             NSString *qPatientID=q[@"columns[3][search][value]"];
             NSString *qPatientName=q[@"columns[4][search][value]"];
             //NSString *qStudyDate=q[@"columns[5][search][value]"];
             NSString *qDate_start=q[@"date_start"];
             NSString *qDate_end=q[@"date_end"];
             NSString *qModality;
             if ([q[@"columns[6][search][value]"]isEqualToString:@"ALL"]) qModality=@"%%";
             else qModality=q[@"columns[6][search][value]"];
             if (!qModality) return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'columns[6][search][value]' (modality) parameter"] contentType:@"application/dicom+json"];
             
             NSString *qStudyDescription=q[@"columns[7][search][value]"];
             
             NSString *rPatientID=r[@"columns[3][search][value]"];
             NSString *rPatientName=r[@"columns[4][search][value]"];
             //NSString *rStudyDate=r[@"columns[5][search][value]"];
             NSString *rDate_start=r[@"date_start"];
             NSString *rDate_end=r[@"date_end"];
             NSString *rModality=r[@"columns[6][search][value]"];
             NSString *rStduyDescription=r[@"columns[7][search][value]"];
             
             
             //same or different context?
             if (
                 !r
                 || [q[@"new"]isEqualToString:@"true"]
                 || (q[@"username"]    && ![q[@"username"]isEqualToString:r[@"username"]])
                 || (q[@"useroid"]     && ![q[@"useroid"]isEqualToString:r[@"useroid"]])
                 || (session           && ![session isEqualToString:r[@"session"]])
                 || (q[@"custodiantitle"]         && ![q[@"custodiantitle"]isEqualToString:r[@"custodiantitle"]])
                 || (q[@"aet"] && ![q[@"aet"]isEqualToString:r[@"aet"]])
                 || (q[@"role"]        && ![q[@"role"]isEqualToString:r[@"role"]])
                 
                 || (q[@"search[value]"] && ![q[@"search[value]"]isEqualToString:r[@"search[value]"]])
                 
                 ||(    qPatientID
                    &&![qPatientID isEqualToString:rPatientID]
                    &&![rPatientID isEqualToString:@""]
                    )
                 ||(    qPatientName
                    &&![qPatientName isEqualToString:rPatientName]
                    &&![rPatientName isEqualToString:@""]
                    )
                 ||(    qDate_start
                    &&![qDate_start isEqualToString:rDate_start]
                    &&![rDate_start isEqualToString:@""]
                    )
                 ||(    qDate_end
                    &&![qDate_end isEqualToString:rDate_end]
                    &&![rDate_end isEqualToString:@""]
                    )
                 ||(  ![qModality isEqualToString:rModality]
                    &&![rModality isEqualToString:@"%%"]
                    )
                 ||(    qStudyDescription
                    &&![qStudyDescription isEqualToString:rStduyDescription]
                    &&![rStduyDescription isEqualToString:@""]
                    )
                 )
             {
                 //LOG_INFO(@"%@",[[request URL]description]);
#pragma mark --different context
#pragma mark reemplazar org por custodianTitle e institucion por aet
                 //find dest
                 NSString *destOID=pacsTitlesDictionary[[q[@"custodiantitle"] stringByAppendingPathExtension:q[@"aet"]]];
                 NSDictionary *destPacs=pacsDictionaries[destOID];
                 
                 NSDictionary *destSql=sql[destPacs[@"sqlQueriesDictionary"]];
                 if (!destSql) return [RSErrorResponse responseWithClientError:404 message:@"%@ [sql not found]",request.path];
                 
                 //local ... simulation qido through database access
                 
                 //LOG_INFO(@"different context with db: %@",destPacs[@"sqlQueriesDictionary"]);
                 
                 if (r){
                     //replace previous request of the session.
                     [Req removeObjectForKey:session];
                     [Total removeObjectForKey:session];
                     [Filtered removeObjectForKey:session];
                     [Date removeObjectForKey:session];
                     if(sPatientID[@"session"])[sPatientID removeObjectForKey:session];
                     if(sPatientName[@"session"])[sPatientName removeObjectForKey:session];
                     //if(sStudyDate[@"session"])[sStudyDate removeObjectForKey:session];
                     if(sDate_start[@"session"])[sDate_start removeObjectForKey:session];
                     if(sDate_end[@"session"])[sDate_end removeObjectForKey:session];
                     if(sModality[@"session"])[sModality removeObjectForKey:session];
                     if(sStudyDescription[@"session"])[sStudyDescription removeObjectForKey:session];
                     
                 }
                 //copy of the sql request of the new context
                 [Req setObject:q forKey:session];
                 
//TODO: remove old sessions
                 [Date setObject:[NSDate date] forKey:session];

                 if(qPatientID)[sPatientID setObject:qPatientID forKey:session];
                 if(qPatientName)[sPatientName setObject:qPatientName forKey:session];
                 //if(qStudyDate)[sStudyDate setObject:qStudyDate forKey:session];
                 if(qDate_start)[sDate_start setObject:qDate_start forKey:session];
                 if(qDate_end)[sDate_end setObject:qDate_end forKey:session];
                 [sModality setObject:qModality forKey:session];
                 if(qStudyDescription)[sStudyDescription setObject:qStudyDescription forKey:session];
                 
//1 create where clause
                 
                 //WHERE study.rejection_state!=2    (or  1=1)
                 //following filters use formats like " AND a like 'b'"
                 NSMutableString *studiesWhere=[NSMutableString stringWithString:destSql[@"studiesWhere"]];

                 //PEP por aet or custodian
                 if ([q[@"aet"] isEqualToString:q[@"custodiantitle"]])
                 {
                     /*
                     [studiesWhere appendFormat:
                      @" AND %@ in %@",
                      destSql[@"accessControlId"],
                      custodianTitlesaetsStrings[q[@"custodiantitle"]]
                      ];
                      */
                 }
                 else
                 {
                     [studiesWhere appendFormat:
                      @" AND %@ in ('%@','%@')",
                      destSql[@"accessControlId"],
                      q[@"aet"],
                      q[@"custodiantitle"]
                      ];
                 }
                 
                 if (q[@"search[value]"] && ![q[@"search[value]"] isEqualToString:@""])
                 {
                     //AccessionNumber q[@"search[value]"]
                     [studiesWhere appendString:
                      [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                       fieldString:destSql[@"AccessionNumber"]
                                       valueString:q[@"search[value]"]
                       ]
                      ];
                 }
                 else
                 {
                     if(qPatientID && [qPatientID length])
                     {
                         [studiesWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                           fieldString:destSql[@"PatientID"]
                                           valueString:qPatientID
                           ]
                          ];
                     }
                     
                     if(qPatientName && [qPatientName length])
                     {
                         //PatientName _00100010 Nombre
                         NSArray *patientNameComponents=[qPatientName componentsSeparatedByString:@"^"];
                         NSUInteger patientNameCount=[patientNameComponents count];
                         
                         [studiesWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                           fieldString:(destSql[@"PatientName"])[0]
                                           valueString:patientNameComponents[0]
                           ]
                          ];
                         
                         if (patientNameCount > 1)
                         {
                             [studiesWhere appendString:
                              [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                               fieldString:(destSql[@"PatientName"])[1]
                                               valueString:patientNameComponents[1]
                               ]
                              ];
                             
                             if (patientNameCount > 2)
                             {
                                 [studiesWhere appendString:
                                  [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                                   fieldString:(destSql[@"PatientName"])[2]
                                                   valueString:patientNameComponents[2]
                                   ]
                                  ];
                                 
                                 if (patientNameCount > 3)
                                 {
                                     [studiesWhere appendString:
                                      [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                                       fieldString:(destSql[@"PatientName"])[3]
                                                       valueString:patientNameComponents[3]
                                       ]
                                      ];
                                     
                                     if (patientNameCount > 4)
                                     {
                                         [studiesWhere appendString:
                                          [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                                           fieldString:(destSql[@"PatientName"])[4]
                                                           valueString:patientNameComponents[4]
                                           ]
                                          ];
                                     }
                                 }
                             }
                         }
                     }
                     
                     if(
                        (qDate_start && [qDate_start length])
                        ||(qDate_end && [qDate_end length])
                        )
                     {
                         NSString *s=nil;
                         if (qDate_start && [qDate_start length]) s=qDate_start;
                         else s=@"";
                         NSString *e=nil;
                         if (qDate_end && [qDate_end length]) e=qDate_end;
                         else e=@"";
                         [studiesWhere appendString:[destSql[@"StudyDate"] sqlFilterWithStart:s end:e]];
                     }
                     
                     //qModality contains ONE modality or joker %%
                     [studiesWhere appendFormat:@" AND %@ like '%%%@%%'", destSql[@"ModalitiesInStudy"], qModality];
                     
                     if(qStudyDescription && [qStudyDescription length])
                     {
                         //StudyDescription _00081030 Descripción
                         [studiesWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                           fieldString:destSql[@"StudyDescription"]
                                           valueString:qStudyDescription
                           ]
                          ];
                     }
                 }
                 LOG_INFO(@"%@",[studiesWhere substringFromIndex:65]);


//2 count
                 NSString *sqlCountQuery=[NSString stringWithFormat:@"%@%@%@%@",
                                          destPacs[@"sqlprolog"],
                                          destSql[@"studiesCountProlog"],
                                          studiesWhere,
                                          destSql[@"studiesCountEpilog"]
                                          ];
                 LOG_DEBUG(@"%@",sqlCountQuery);
                 NSMutableData *countData=[NSMutableData data];
                 if (task(@"/bin/bash",@[@"-s"],[sqlCountQuery dataUsingEncoding:NSUTF8StringEncoding],countData))
                     [RSErrorResponse responseWithClientError:404 message:@"%@",@"can not access the db"];//NotFound
                 NSString *countString=[[NSString alloc]initWithData:countData encoding:NSUTF8StringEncoding];
                 // max (max records filtered para evitar que filtros insuficientes devuelvan casi todos los registros... lo que devolvería un resultado inútil.
                 recordsTotal=[countString intValue];
                 int maxCount=[q[@"max"]intValue];
                 LOG_INFO(@"total:%d, max:%d",recordsTotal,maxCount);
                 if (recordsTotal > maxCount) return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:[NSString stringWithFormat:@"you need a narrower filter. The browser table accepts up to %d matches. %d matches were found",maxCount, recordsTotal]] contentType:@"application/dicom+json"];

                 if (!recordsTotal) return [RSDataResponse
                                            responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:@{
                                                      @"draw":q[@"draw"],
                                                      @"recordsTotal":@0,
                                                      @"recordsFiltered":@0,
                                                      @"data":@[]
                                                      }]
                                     contentType:@"application/dicom+json"
                                     ];
                 else
                 {
                     //order is performed later, from mutableDictionary
//3 select
                     NSString *sqlDataQuery=[NSString stringWithFormat:@"%@%@%@%@",
                                             destPacs[@"sqlprolog"],
                                             destSql[@"datatablesStudiesProlog"],
                                             studiesWhere,
                                             [NSString stringWithFormat: destSql[@"datatablesStudiesEpilog"],session,
                                                 session
                                              ]
                                             ];

                     NSMutableArray *studiesArray=jsonMutableArray(sqlDataQuery, [destPacs[@"sqlstringencoding"]unsignedIntegerValue]);

                     [Total setObject:studiesArray forKey:session];
                     [Filtered setObject:[studiesArray mutableCopy] forKey:session];
                 }
                 
             }//end diferent context
             else
             {
                 
#pragma mark --same context
                 
                 recordsTotal=[Total[session] count];
                 //LOG_INFO(@"same context recordsTotal: %d ",recordsTotal);
                 
                 //subfilter?
                 // in case there is subfilter, derive BFiltered from BTotal
                 //https://developer.apple.com/reference/foundation/nsmutablearray/1412085-filterusingpredicate?language=objc
                 
                 if (recordsTotal > 0)
                 {
                     BOOL toBeFiltered=false;
                     
                     NSRegularExpression *PatientIDRegex=nil;
                     if(qPatientID && ![qPatientID isEqualToString:sPatientID[session]])
                     {
                         toBeFiltered=true;
                         PatientIDRegex=[NSRegularExpression regularExpressionWithPattern:[NSString regexDicomString:qPatientID withFormat:@"datatables\\/patient\\?PatientID=%@.*"] options:0 error:NULL];
                     }
                     
                     NSRegularExpression *PatientNameRegex=nil;
                     if(qPatientName && ![qPatientName isEqualToString:sPatientName[session]])
                     {
                         toBeFiltered=true;
                         PatientNameRegex=[NSRegularExpression regularExpressionWithPattern:[NSString regexDicomString:qPatientName withFormat:@"%@.*"] options:NSRegularExpressionCaseInsensitive error:NULL];
                     }
                     
                     NSString *until;
                     if(   qDate_end
                        && (  !sDate_end[session]
                            || ([qDate_end compare:sDate_end[session]]==NSOrderedAscending)
                            )
                        )
                     {
                         toBeFiltered=true;
                         until=qDate_end;
                     }
                     
                     NSString *since;
                     if(   qDate_start
                        && (  !sDate_start[session]
                            || ([qDate_start compare:sDate_start[session]]==NSOrderedDescending)
                            )
                        )
                     {
                         toBeFiltered=true;
                         since=qDate_start;
                     }
                     
                     NSString *modalitySelected=nil;
                     //sModality contains the last selected modality within the same context
                     if(![qModality isEqualToString:sModality[session]])
                     {
                         toBeFiltered=true;
                         modalitySelected=qModality;
                     }
                     else modalitySelected=sModality[session];
                     
                     NSRegularExpression *StudyDescriptionRegex=nil;
                     if(qStudyDescription  && ![qStudyDescription isEqualToString:sStudyDescription[session]])
                     {
                         toBeFiltered=true;
                         StudyDescriptionRegex=[NSRegularExpression regularExpressionWithPattern:[NSString regexDicomString:qStudyDescription withFormat:@"%@.*"] options:NSRegularExpressionCaseInsensitive error:NULL];
                     }
                     
                     if(toBeFiltered)
                     {
                         //filter from BTotal copy
                         [Filtered removeObjectForKey:session];
                         [Filtered setObject:[Total[session] mutableCopy] forKey:session];
                         
                         //create compound predicate
                         NSPredicate *compoundPredicate = [NSPredicate predicateWithBlock:^BOOL(NSArray *row, NSDictionary *bindings) {
                             if (PatientIDRegex)
                             {
                                 //LOG_INFO(@"patientID filter");
                                 if (![PatientIDRegex numberOfMatchesInString:row[3] options:0 range:NSMakeRange(0,[row[3] length])]) return false;
                             }
                             if (PatientNameRegex)
                             {
                                 //LOG_INFO(@"patientName filter");
                                 if (![PatientNameRegex numberOfMatchesInString:row[4] options:0 range:NSMakeRange(0,[row[4] length])]) return false;
                             }
                             if (until)
                             {
                                 //LOG_INFO(@"until filter");
                                 if ([until compare:row[5]]==NSOrderedDescending) return false;
                             }
                             if (since)
                             {
                                 //LOG_INFO(@"since filter");
                                 if ([since compare:row[5]]==NSOrderedAscending) return false;
                             }
                             //row[6] contains modalitiesInStudies. Ej: CT\OT
                             if (![row[6] containsString:modalitySelected]) return false;

                             if (StudyDescriptionRegex)
                             {
                                 //LOG_INFO(@"description filter");
                                 if (![StudyDescriptionRegex numberOfMatchesInString:row[7] options:0 range:NSMakeRange(0,[row[7] length])]) return false;
                             }
                             return true;
                         }];
                         
                         [Filtered[session] filterUsingPredicate:compoundPredicate];
                     }
                 }
             }
#pragma mark --order
             if (q[@"order[0][column]"] && q[@"order[0][dir]"])
             {
                 LOG_INFO(@"ordering with %@, %@",q[@"order[0][column]"],q[@"order[0][dir]"]);
                 
                 int column=[q[@"order[0][column]"]intValue];
                 if ([q[@"order[0][dir]"]isEqualToString:@"desc"])
                 {
                     [Filtered[session] sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                         return [obj2[column] caseInsensitiveCompare:obj1[column]];
                     }];
                 }
                 else
                 {
                     [Filtered[session] sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                         return [obj1[column] caseInsensitiveCompare:obj2[column]];
                     }];
                 }
             }
             
#pragma mark --response
             
             NSMutableDictionary *resp = [NSMutableDictionary dictionary];
             NSUInteger recordsFiltered=[Filtered[session]count];
             [resp setObject:q[@"draw"] forKey:@"draw"];
             [resp setObject:[NSNumber numberWithInt:recordsTotal] forKey:@"recordsTotal"];
             [resp setObject:[NSNumber numberWithUnsignedInteger:recordsFiltered] forKey:@"recordsFiltered"];
             
             if (!recordsFiltered)  return [RSDataResponse
                                            responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:@{@"draw":q[@"draw"],@"recordsTotal":@0,@"recordsFiltered":@0,@"data":@[]}]
                                            contentType:@"application/dicom+json"
                                            ];
             else
             {
                 //start y length
                 long ps=[q[@"start"]intValue];
                 long pl=[q[@"length"]intValue];
                 //LOG_INFO(@"paging desired (start=[%ld],filas=[%ld],last=[%lu])",ps,pl,recordsFiltered-1);
                 if (ps < 0) ps=0;
                 if (ps > recordsFiltered-1) ps=0;
                 if (ps+pl+1 > recordsFiltered) pl=recordsFiltered-ps;
                 //LOG_INFO(@"paging applied (start=[%ld],filas=[%ld],last=[%lu])",ps,pl,recordsFiltered-1);
                 NSArray *page=[Filtered[session] subarrayWithRange:NSMakeRange(ps,pl)];
                 if (!page)page=@[];
                 [resp setObject:page forKey:@"data"];
             }
             
             return [RSDataResponse
                     responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:resp]
                     contentType:@"application/dicom+json"
                     ];
         }
                                                                                                                                          (request));}];
        
#pragma mark datatables/patient
        /*
         ventana emergente con todos los estudios del paciente
         "datatables/patient?PatientID=33333333&IssuerOfPatientID.UniversalEntityID=NULL&session=1"
         */
        NSRegularExpression *dtpatientRegex = [NSRegularExpression regularExpressionWithPattern:@"/datatables/patient" options:0 error:NULL];
        [httpdicomServer addHandler:@"GET" regex:dtpatientRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];
             

             NSDictionary *q=request.query;
             
             NSString *session=q[@"session"];
             if (!session || [session isEqualToString:@""]) return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'session' parameter"] contentType:@"application/dicom+json"];
             
             if (!q[@"PatientID"]) return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"studies of patient query without required 'patientID' parameter"] contentType:@"application/dicom+json"];
             
             //WHERE study.rejection_state!=2    (or  1=1)
             //following filters use formats like " AND a like 'b'"
             
             //find dest
             NSString *destOID=pacsTitlesDictionary[[q[@"custodiantitle"] stringByAppendingPathExtension:q[@"aet"]]];
             NSDictionary *destPacs=pacsDictionaries[destOID];
             
             NSDictionary *destSql=sql[destPacs[@"sqlQueriesDictionary"]];
             if (!destSql) return [RSErrorResponse responseWithClientError:404 message:@"%@ [sql not found]",request.path];
             
             NSMutableString *studiesWhere=[NSMutableString stringWithString:destSql[@"studiesWhere"]];
             [studiesWhere appendString:
              [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                               fieldString:destSql[@"PatientID"]
                               valueString:q[@"PatientID"]
               ]
              ];
             //PEP por custodian aets
             [studiesWhere appendFormat:
              @" AND %@ in ('%@')",
              destSql[@"accessControlId"],
              [custodianTitlesaets[q[@"custodiantitle"]] componentsJoinedByString:@"','"]
              ];

             LOG_INFO(@"WHERE %@",[studiesWhere substringFromIndex:38]);
             

             NSString *sqlDataQuery=[NSString stringWithFormat:@"%@%@%@%@",
                                     destPacs[@"sqlprolog"],
                                     destSql[@"datatablesStudiesProlog"],
                                     studiesWhere,
                                     [NSString stringWithFormat: destSql[@"datatablesStudiesEpilog"],session,
                                      session
                                      ]
                                     ];
             
             NSMutableArray *studiesArray=jsonMutableArray(sqlDataQuery, [destPacs[@"sqlstringencoding"]unsignedIntegerValue]);
             
             //sorted study date (5) desc
             [studiesArray sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                 return [obj2[5] caseInsensitiveCompare:obj1[5]];
             }];
             
             
             NSMutableDictionary *resp = [NSMutableDictionary dictionary];
             if (q[@"draw"])[resp setObject:q[@"draw"] forKey:@"draw"];
             NSNumber *count=[NSNumber numberWithUnsignedInteger:[studiesArray count]];
             [resp setObject:count forKey:@"recordsTotal"];
             [resp setObject:count forKey:@"recordsFiltered"];
             [resp setObject:studiesArray forKey:@"data"];
             return [RSDataResponse
                     responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:resp]
                     contentType:@"application/dicom+json"
                     ];
         }
                                                                                                                                          (request));}];
        
        
#pragma mark datatables/series
        //"datatables/series?AccessionNumber=22&IssuerOfAccessionNumber.UniversalEntityID=NULL&StudyIUID=2.16.858.2.10000675.72769.20160411084701.1.100&session=1"
        NSRegularExpression *dtseriesRegex = [NSRegularExpression regularExpressionWithPattern:@"/datatables/series" options:0 error:NULL];
        [httpdicomServer addHandler:@"GET" regex:dtseriesRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];
             

             NSDictionary *q=request.query;
             NSString *session=q[@"session"];
             if (!session || [session isEqualToString:@""]) return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'session' parameter"] contentType:@"application/dicom+json"];
             
             
             //find dest
             NSString *destOID=pacsTitlesDictionary[[q[@"custodiantitle"] stringByAppendingPathExtension:q[@"aet"]]];
             NSDictionary *destPacs=pacsDictionaries[destOID];
             
             NSDictionary *destSql=sql[destPacs[@"sqlQueriesDictionary"]];
             if (!destSql) return [RSErrorResponse responseWithClientError:404 message:@"%@ [sql not found]",request.path];
             NSString *where;
             NSString *AccessionNumber=q[@"AccessionNumber"];
             NSString *StudyInstanceUID=q[@"StudyInstanceUID"];
             if (
                    [destPacs[@"preferredStudyIdentificator"] isEqualToString:@"AccessionNumber"]
                 && AccessionNumber
                 && ![AccessionNumber isEqualToString:@"NULL"])
             {
                 NSString *IssuerOfAccessionNumber=q[@"IssuerOfAccessionNumber.UniversalEntityID"];
                 if (IssuerOfAccessionNumber && ![IssuerOfAccessionNumber isEqualToString:@"NULL"]) where=[NSString stringWithFormat:@"%@ AND %@='%@' AND %@='%@'", destSql[@"seriesWhere"],destSql[@"AccessionNumber"],AccessionNumber,destSql[@"IssuerOfAccessionNumber"],IssuerOfAccessionNumber];
                 else where=[NSString stringWithFormat:@"%@ AND %@='%@'",destSql[@"seriesWhere"],destSql[@"AccessionNumber"],AccessionNumber];
                 
             }
             else if (StudyInstanceUID && ![StudyInstanceUID isEqualToString:@"NULL"])
                 where=[NSString stringWithFormat:@"%@ AND %@='%@'",destSql[@"seriesWhere"],destSql[@"StudyInstanceUID"],StudyInstanceUID];
             else return [RSDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'AccessionNumber' or 'StudyInstanceUID' parameter"] contentType:@"application/dicom+json"];
             
             
             LOG_INFO(@"WHERE %@",[where substringFromIndex:38]);

             NSString *sqlDataQuery=[NSString stringWithFormat:@"%@%@%@%@",
                                     destPacs[@"sqlprolog"],
                                     destSql[@"datatablesSeriesProlog"],
                                     where,
                                     [NSString stringWithFormat:
                                      destSql[@"datatablesSeriesEpilog"],
                                      session,
                                      session
                                      ]
                                     ];
             
             NSMutableArray *seriesArray=jsonMutableArray(sqlDataQuery, [destPacs[@"sqlstringencoding"]unsignedIntegerValue]);
             //LOG_INFO(@"series array:%@",[seriesArray description]);
             
             NSMutableDictionary *resp = [NSMutableDictionary dictionary];
             if (q[@"draw"])[resp setObject:q[@"draw"] forKey:@"draw"];
             NSNumber *count=[NSNumber numberWithUnsignedInteger:[seriesArray count]];
             [resp setObject:count forKey:@"recordsTotal"];
             [resp setObject:count forKey:@"recordsFiltered"];
             [resp setObject:seriesArray forKey:@"data"];
             return [RSDataResponse
                     responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:resp]
                     contentType:@"application/dicom+json"
                     ];
         }
                                                                                                                                          (request));}];

        
#pragma mark IHEInvokeImageDisplay
        //IHEInvokeImageDisplay
        //?requestType=STUDY
        //&accessionNumber=1
        //&viewerType=IHE_BIR
        //&diagnosticQuality=true
        //&keyImagesOnly=false
        //&custodianOID=xxx
        //&proxyURI=yyy
        NSRegularExpression *iheiidRegex = [NSRegularExpression regularExpressionWithPattern:@"/IHEInvokeImageDisplay" options:0 error:NULL];
        [httpdicomServer addHandler:@"GET" regex:iheiidRegex processBlock:
         ^(RSRequest* request, RSCompletionBlock completionBlock){completionBlock(^RSResponse* (RSRequest* request)
         {
             LOG_DEBUG(@"client: %@",request.remoteAddressString);
             //using NSURLComponents instead of RSRequest
             NSURLComponents *urlComponents=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
             NSArray *pComponents=[urlComponents.path componentsSeparatedByString:@"/"];

             NSDictionary *q=request.query;
             
             //(1) b= html5dicomURL
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             LOG_INFO(@"%@%@?%@",b,p,requestURL.query);
             
             
             //(2) accept requestType STUDY / SERIES only
             NSString *requestType=q[@"requestType"];
             if (
                 !requestType
                 ||!
                 (  [requestType isEqualToString:@"STUDY"]
                  ||[requestType isEqualToString:@"SERIES"]
                  )
                 ) return [RSDataResponse responseWithText:[NSString stringWithFormat:@"missing requestType param in %@%@?%@",b,p,requestURL.query]];
             
             //session
             if (!q[@"session"]) return [RSDataResponse responseWithText:[NSString stringWithFormat:@"missing session param in %@%@?%@",b,p,requestURL.query]];
             
             
             //custodianURI
             
             if (!q[@"custodianOID"]) return [RSDataResponse responseWithText:[NSString stringWithFormat:@"missing custodianOID param in %@%@?%@",b,p,requestURL.query]];
             NSString *custodianURI;
             if ((pacsDictionaries[q[@"custodianOID"]])[@"islocalhosted"])custodianURI=[NSString stringWithFormat:@"http://localhost:%lld",port];
             else custodianURI=(pacsDictionaries[q[@"custodianOID"]])[@"publicuri"];
             if (!@"custodianURI") return [RSDataResponse responseWithText:[NSString stringWithFormat:@"invalid custodianOID param in %@%@?%@",b,p,requestURL.query]];
             
             
             //proxyURI
             NSString *proxyURI=q[@"proxyURI"];
             if (!proxyURI) proxyURI=b;
             
             //redirect to specific manifest
             NSMutableString *manifest=[NSMutableString string];
             
             NSString *viewerType=q[@"viewerType"];
             if (  !viewerType
                 || [viewerType isEqualToString:@"IHE_BIR"]
                 || [viewerType isEqualToString:@"weasis"]
                 )
             {
                 [manifest appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r"];
                 NSString *additionalParameters=(pacsDictionaries[q[@"custodianOID"]])[@"wadoadditionalparameters"];
                 if (!additionalParameters)additionalParameters=@"";
                 [manifest appendFormat:@"<wado_query xmlns=\"http://www.weasis.org/xsd\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" wadoURL=\"%@\" requireOnlySOPInstanceUID=\"false\" additionnalParameters=\"%@&amp;session=%@&amp;custodianOID=%@\" overrideDicomTagsList=\"\">",
                  proxyURI,
                  additionalParameters,
                  q[@"session"],
                  q[@"custodianOID"]
                  ];
                 
                 NSString *manifestWeasisURI;
                 if ([requestType isEqualToString:@"STUDY"])
                 {
                     if (q[@"accessionNumber"]) manifestWeasisURI=[NSString stringWithFormat:@"%@/manifest/weasis/studies?AccessionNumber=%@&custodianOID=%@",custodianURI,q[@"accessionNumber"],q[@"custodianOID"]];
                     else if (q[@"studyUID"]) manifestWeasisURI=[NSString stringWithFormat:@"%@/manifest/weasis/studies?StudyInstanceUID=%@&custodianOID=%@",custodianURI,q[@"studyUID"],q[@"custodianOID"]];
                     else return [RSDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                 }
                 else
                 {
                     //SERIES
                     if (q[@"studyUID"] && q[@"seriesUID"]) manifestWeasisURI=[NSString stringWithFormat:@"%@/manifest/weasis/studies/%@/series/%@?custodianOID=%@",custodianURI,q[@"studyUID"],q[@"seriesUID"],q[@"custodianOID"]];
                     else return [RSDataResponse responseWithText:[NSString stringWithFormat:@"requestType=SERIES requires params studyUID and seriesUID in %@%@?%@",b,p,requestURL.query]];
                 }
                 LOG_INFO(@"%@",manifestWeasisURI);
                 [manifest appendFormat:@"%@\r</wado_query>\r",[NSString stringWithContentsOfURL:[NSURL URLWithString:manifestWeasisURI] encoding:NSUTF8StringEncoding error:nil]];
                 LOG_INFO(@"%@",manifest);
                 
                 if ([manifest length]<350) [RSDataResponse responseWithText:[NSString stringWithFormat:@"zero objects for %@%@?%@",b,p,requestURL.query]];
                 
                 
                 if (![custodianURI isEqualToString:@"http://localhost"])
                 {
                     //get series not available in dev0
                     
                     NSXMLDocument *xmlDocument=[[NSXMLDocument alloc]initWithXMLString:manifest options:0 error:nil];
                     NSArray *seriesWadorsArray = [xmlDocument nodesForXPath:@"wado_query/Patient/Study/Series" error:nil];
                     for (NSXMLNode *node in seriesWadorsArray)
                     {
                         NSString *seriesWadors=[node stringValue];// /studies/{studies}/series/{series}
                         
                         //cantidad de instancias en la serie en dev0?
                         
                     }
                 }
                 RSDataResponse *response=[RSDataResponse responseWithData:[[[LFCGzipUtility gzipData:[manifest dataUsingEncoding:NSUTF8StringEncoding]] base64EncodedStringWithOptions:0]dataUsingEncoding:NSUTF8StringEncoding] contentType:@"application/x-gzip"];
                 [response setValue:@"Base64" forAdditionalHeader:@"Content-Transfer-Encoding"];//https://tools.ietf.org/html/rfc2045
                 
                 return response;
             }
             else if ([viewerType isEqualToString:@"cornerstone"])
             {
                 //cornerstone
                 NSMutableDictionary *cornerstone=[NSMutableDictionary dictionary];
                 
                 //qido uri
                 NSString *qidoSeriesString;
                 if ([requestType isEqualToString:@"STUDY"])
                 {
                     if (q[@"accessionNumber"]) qidoSeriesString=[NSString stringWithFormat:@"%@/series?AccessionNumber=%@",(pacsDictionaries[q[@"custodianOID"]])[@"qido"],q[@"accessionNumber"]];
                     else if (q[@"studyUID"]) qidoSeriesString=[NSString stringWithFormat:@"%@/series?StudyInstanceUID=%@",(pacsDictionaries[q[@"custodianOID"]])[@"qido"],q[@"studyUID"]];
                     else return [RSDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                 }
                 else
                 {
                     //SERIES
                     if (q[@"studyUID"] && q[@"seriesUID"]) qidoSeriesString=[NSString stringWithFormat:@"%@/series?StudyInstanceUID=%@&SeriesInstanceUID=%@",(pacsDictionaries[q[@"custodianOID"]])[@"qido"],q[@"studyUID"],q[@"seriesUID"]];
                     else return [RSDataResponse responseWithText:[NSString stringWithFormat:@"requestType=SERIES requires params studyUID and seriesUID in %@%@?%@",b,p,requestURL.query]];
                 }
                 LOG_DEBUG(@"%@",qidoSeriesString);
                 
                 NSMutableArray *seriesArray=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:qidoSeriesString]] options:NSJSONReadingMutableContainers error:nil];
                 
                 [cornerstone setObject:((((seriesArray[0])[@"00100010"])[@"Value"])[0])[@"Alphabetic"] forKey:@"patientName"];
                 [cornerstone setObject:(((seriesArray[0])[@"00100020"])[@"Value"])[0] forKey:@"patientId"];
                 NSString *s=(((seriesArray[0])[@"00080020"])[@"Value"])[0];
                 NSString *StudyDate=[NSString stringWithFormat:@"%@-%@-%@",
                                      [s substringWithRange:NSMakeRange(0,4)],
                                      [s substringWithRange:NSMakeRange(4,2)],
                                      [s substringWithRange:NSMakeRange(6,2)]];
                 [cornerstone setObject:StudyDate forKey:@"studyDate"];
                 [cornerstone setObject:(((seriesArray[0])[@"00080061"])[@"Value"])[0] forKey:@"modality"];
                 NSString *studyDescription=(((seriesArray[0])[@"00081030"])[@"Value"])[0];
                 if (!studyDescription) studyDescription=@"";
                 [cornerstone setObject:studyDescription forKey:@"studyDescription"];//
                 [cornerstone setObject:@999 forKey:@"numImages"];
                 NSString *studyId=(((seriesArray[0])[@"00200010"])[@"Value"])[0];
                 if (!studyId)studyId=@"";
                 [cornerstone setObject:studyId forKey:@"studyId"];
                 NSMutableArray *seriesList=[NSMutableArray array];
                 [cornerstone setObject:seriesList forKey:@"seriesList"];
                 for (NSDictionary *seriesQido in seriesArray)
                 {
                     if (
                         !([((seriesQido[@"00080060"])[@"Value"])[0] isEqualToString:@"OT"])
                         &&!([((seriesQido[@"00080060"])[@"Value"])[0] isEqualToString:@"DOC"]))
                     {
                         //cornerstone no muestra los documentos encapsulados
                         NSMutableDictionary *seriesCornerstone=[NSMutableDictionary dictionary];
                         [seriesList addObject:seriesCornerstone];
                         NSString *seriesDescription=((seriesQido[@"0008103E"])[@"Value"])[0];
                         if (!seriesDescription)seriesDescription=@"";
                         [seriesCornerstone setObject:seriesDescription forKey:@"seriesDescription"];
                         [seriesCornerstone setObject:((seriesQido[@"00200011"])[@"Value"])[0] forKey:@"seriesNumber"];
                         NSMutableArray *instanceList=[NSMutableArray array];
                         [seriesCornerstone setObject:instanceList forKey:@"instanceList"];
                         //get instances for the series
                         
                         NSString *qidoInstancesString=
                         [NSString stringWithFormat:@"%@/instances?StudyInstanceUID=%@&SeriesInstanceUID=%@",
                          (pacsDictionaries[q[@"custodianOID"]])[@"qido"],
                          q[@"studyUID"],
                          ((seriesQido[@"0020000E"])[@"Value"])[0]
                          ];
                         LOG_INFO(@"%@",qidoInstancesString);
                         NSData *qidoInstanceResp=[NSData dataWithContentsOfURL:[NSURL URLWithString:qidoInstancesString]];
                         NSMutableArray *instancesArray=[NSJSONSerialization JSONObjectWithData:qidoInstanceResp options:NSJSONReadingMutableContainers error:nil];
                         
                         //classify instancesArray by instanceNumber
                         
                         [instancesArray sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                             if ([((obj1[@"00200013"])[@"Value"])[0]intValue]<[((obj2[@"00200013"])[@"Value"])[0]intValue])
                                 return NSOrderedAscending;
                             return NSOrderedDescending;
                         }];
                         
                         
                         
                         for (NSDictionary *instance in instancesArray)
                         {
                             NSString *wadouriInstance=[NSString stringWithFormat:@"%@?requestType=WADO&studyUID=%@&seriesUID=%@&objectUID=%@&session=%@&custodianOID=%@",proxyURI,
                                                        q[@"studyUID"],
                                                        ((seriesQido[@"0020000E"])[@"Value"])[0],
                                                        ((instance[@"00080018"])[@"Value"])[0],
                                                        q[@"session"],
                                                        q[@"custodianOID"]
                                                        ];
                             [instanceList addObject:@{
                                                       @"imageId":wadouriInstance
                                                       }];
                         }
                     }
                 }
                 NSData *cornerstoneJson=[NSJSONSerialization dataWithJSONObject:cornerstone options:0 error:nil];
                 LOG_DEBUG(@"cornerstone manifest :\r\n%@",[[NSString alloc] initWithData:cornerstoneJson encoding:NSUTF8StringEncoding]);
                 return [RSDataResponse responseWithData:cornerstoneJson contentType:@"application/json"];
             }
             else if ([viewerType isEqualToString:@"MHD-I"])
             {
                 //MHD-I
                 if ([requestType isEqualToString:@"STUDY"])
                 {
                     NSString *accessionNumber=q[@"accessionNumber"];
                     NSString *studyUID=q[@"studyUID"];
                     if (accessionNumber)
                     {
                         
                     }
                     else if (studyUID)
                     {
                         
                     }
                     else return [RSDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                     
                 }
                 else
                 {
                     //SERIES
                 }
             }
             return [RSDataResponse responseWithText:[NSString stringWithFormat:@"unknown viewerType in %@%@?%@",b,p,requestURL.query]];
         }
                                                                                                                                          (request));}];
        
#pragma mark -
#pragma mark run
        NSError *error=nil;
        
        [httpdicomServer startWithPort:port maxPendingConnections:16 error:&error];
        while (true) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
        }        
    }//end autorelease pool
}
