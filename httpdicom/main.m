//
//  main.m
//  httpdicom
//
//  Created by saluduy on 20160302.
//  Copyright (c) 2016 ridi.salud.uy. All rights reserved.
//
/*
 Copyright:  Copyright (c) jacques.fauquex@opendicom.com All Rights Reserved.
 
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

#import <Cocoa/Cocoa.h>


#import "GCDWebServerResponse.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerPrivate.h"
#import "LFCGzipUtility.h"
#import "ZZArchiveEntry.h"
#import "ZZArchive.h"
#import "ZZConstants.h"
#import "ZZChannel.h"
#import "ZZError.h"

#import "NSString+PCS.h"
#import "NSData+PCS.h"

static NSData *rn;
static NSData *rnhh;
static NSData *rnrn;
static NSData *contentType;
static NSData *CDAOpeningTag;
static NSData *CDAClosingTag;
static NSTimeInterval timeout=300;

// A=Datatables Patient Studies
// B=Datatables Studies
// C=Datatables Series contenidas
static NSMutableDictionary *Date;
static NSMutableDictionary *Req;
static NSMutableDictionary *Total;
static NSMutableDictionary *Filtered;
static NSMutableDictionary *sPatientID;
static NSMutableDictionary *sPatientName;
static NSMutableDictionary *sStudyDate;
static NSMutableDictionary *sModalitiesInStudy;
static NSMutableDictionary *sStudyDescription;
static BOOL _run;

static void _SignalHandler(int signal) {
    _run = NO;
    printf("\n");
}

int task(NSString *launchPath, NSArray *launchArgs, NSData *writeData, NSMutableData *readData)
{
    NSTask *task=[[NSTask alloc]init];
    [task setLaunchPath:launchPath];
    [task setArguments:launchArgs];
    //NSLog(@"%@",[task arguments]);
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
    if (terminationStatus!=0) NSLog(@"ERROR task terminationStatus: %d",terminationStatus);
    return terminationStatus;
}

int main(int argc, const char* argv[]) {
    BOOL success = NO;

    /*
     syntax: httpdicom
     
     [1] path to oids.plist
     [2] devOid[0] (OID del dcm4chee-arc-light del PCS)
     [3] devOid[1] (device, workstation, pacs conectado al PCS local
     [4] ...
     */
    
    @autoreleasepool {
        NSFileManager *fileManager=[NSFileManager defaultManager];
        Req=[NSMutableDictionary dictionary];
        Total=[NSMutableDictionary dictionary];
        Filtered=[NSMutableDictionary dictionary];
        Date=[NSMutableDictionary dictionary];
        sPatientID=[NSMutableDictionary dictionary];
        sPatientName=[NSMutableDictionary dictionary];
        sStudyDate=[NSMutableDictionary dictionary];
        sModalitiesInStudy=[NSMutableDictionary dictionary];
        sStudyDescription=[NSMutableDictionary dictionary];
        
        NSDateFormatter *dicomDTFormatter = [[NSDateFormatter alloc] init];
        [dicomDTFormatter setDateFormat:@"yyyyMMddHHmmss"];

        rn = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        rnrn = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        rnhh = [@"\r\n--" dataUsingEncoding:NSASCIIStringEncoding];
        contentType=[@"Content-Type: " dataUsingEncoding:NSASCIIStringEncoding];
        CDAOpeningTag=[@"<ClinicalDocument" dataUsingEncoding:NSASCIIStringEncoding];
        CDAClosingTag=[@"</ClinicalDocument>" dataUsingEncoding:NSASCIIStringEncoding];
        
        //regex for url validation
        NSRegularExpression *UIRegex = [NSRegularExpression regularExpressionWithPattern:@"^[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*$" options:0 error:NULL];
        NSRegularExpression *SHRegex = [NSRegularExpression regularExpressionWithPattern:@"^(?:\\s*)([^\\r\\n\\f\\t]*[^\\r\\n\\f\\t\\s])(?:\\s*)$" options:0 error:NULL];

        NSArray *args=[[NSProcessInfo processInfo] arguments];
        NSDictionary *devs=[NSDictionary dictionaryWithContentsOfFile:[args[1]stringByExpandingTildeInPath]];
        //NSLog(@"devs:\r%@",[devs description]);

        
        NSMutableSet *orgis=[NSMutableSet set];
        NSMutableSet *orgts=[NSMutableSet set];
        NSMutableSet *sqlset=[NSMutableSet set];
        
        for (NSDictionary *d in [devs allValues])
        {
            [orgis addObject:[d objectForKey:@"pcsi"]];
            [orgts addObject:[d objectForKey:@"pcst"]];
            NSString *s=[d objectForKey:@"sql"];
            if (s) [sqlset addObject:s];
        }
        NSArray *orgisArray=[orgis allObjects];
        NSData *orgisData = [NSJSONSerialization dataWithJSONObject:orgisArray options:0 error:nil];
        NSArray *orgtsArray=[orgts allObjects];
        NSData *orgtsData = [NSJSONSerialization dataWithJSONObject:orgtsArray options:0 error:nil];

        //crear un dictionario con índice orgi y orgt y objeto el json corresondiente de lista de aet o de lista de aei
        NSMutableDictionary *orgtsaets=[NSMutableDictionary dictionary];
        NSMutableDictionary *orgisaeis=[NSMutableDictionary dictionary];
        for (NSString *orgi in orgisArray)
        {
            //para cada org
            NSString *orgt=[orgtsArray objectAtIndex:[orgisArray indexOfObject:orgi]];
            NSMutableArray *orgtaets=[NSMutableArray array];
            NSMutableArray *orgiaeis=[NSMutableArray array];
            for (NSString *k in [devs allKeys])
            {
                NSDictionary *d=[devs objectForKey:k];
                if ([[d objectForKey:@"pcsi"]isEqualToString:orgi])
                {
                    [orgtaets addObject:[d objectForKey:@"dicomaet"]];
                    [orgiaeis addObject:k];
                }
            }
            [orgtsaets setValue:orgtaets forKey:orgt];
            [orgisaeis setValue:orgiaeis forKey:orgi];
        }
        NSUInteger devCount=[args count]-2;
        NSArray *devOids=[args subarrayWithRange:NSMakeRange(2,devCount)];
        NSDictionary *dev0=devs[devOids[0]];

        //-loglevel 0=debug, 1=verbose, 2=info
        [GCDWebServer setLogLevel:[[dev0 objectForKey:@"loglevel"]intValue]];
        
        NSString *IIDURL=dev0[@"pcsurl"];
        NSString *resources=[dev0[@"pcsresources"]stringByExpandingTildeInPath];
        NSString *jnlp=[[NSString stringWithContentsOfFile:[resources stringByAppendingPathComponent:@"weasis/weasis.jnlp"] encoding:NSUTF8StringEncoding error:nil]stringByReplacingOccurrencesOfString:@"{IIDURL}" withString:IIDURL];
        
        //auditPath
        NSString *auditPath=[dev0[@"pcsaudit"]stringByExpandingTildeInPath];
        
        //storescu
        NSString *storescu=[dev0[@"storescu"]stringByExpandingTildeInPath];
        NSArray *storescuArgs=dev0[@"storescuargs"];
        
        //pcsPort
        int pcsPort=[[dev0 objectForKey:@"pcsport"]intValue];
        GCDWebServer* httpdicomServer = [[GCDWebServer alloc] init];
        
        //sql configurations
        NSMutableDictionary *sql=[NSMutableDictionary dictionary];
        for (NSString *s in sqlset)
        {
            [sql setObject:[NSDictionary dictionaryWithContentsOfFile:[s stringByExpandingTildeInPath]] forKey:s];
        }

#pragma mark -
#pragma mark no handler
        NSRegularExpression *defaultregex = [NSRegularExpression regularExpressionWithPattern:@"^/.*" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:defaultregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
                                    NSURL *requestURL=request.URL;
                                    NSString *bSlash=requestURL.baseURL.absoluteString;
                                    NSString *b=[bSlash substringToIndex:[bSlash length]-1];
                                    NSString *p=requestURL.path;
                                    NSString *q=requestURL.query;
                                    GWS_LOG_INFO(@"no handler for:(%@) %@%@?%@",request.method,b,p,q);
                                    return [GCDWebServerDataResponse responseWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://opendicom.com"]] contentType:@"text/html"];
                                }
         ];

#pragma mark -
#pragma mark _______localhost dicomweb_______

#pragma mark qido studies series instances
        
        NSRegularExpression *qidoregex = [NSRegularExpression regularExpressionWithPattern:@"^/studies$|^/series$|^/instances$" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:qidoregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSString *q=request.URL.query;
             NSString *qidoString;
             if (q) qidoString=[[dev0 objectForKey:request.URL.path]stringByAppendingString:q];
             else    qidoString=[dev0 objectForKey:request.URL.path];
             GWS_LOG_INFO(@"dev0 qido: %@",qidoString);
             NSData *responseData=[NSData dataWithContentsOfURL:
                                   [NSURL URLWithString:qidoString]];
             if (!responseData) return
                [GCDWebServerErrorResponse
                 responseWithClientError:kGCDWebServerHTTPStatusCode_FailedDependency
                 message:@"dev0 qido: %@",qidoString
                 ];

             if (![responseData length]) return
             [GCDWebServerErrorResponse
              responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound
              message:@"dev0 qido: %@",qidoString
              ];
             return [GCDWebServerDataResponse
                     responseWithData:responseData
                     contentType:@"application/dicom+json"
                     ];
         }
         ];

#pragma mark datatables/studies
        /*
         query ajax with params:
         agregate 00080090 in other accesible PCS...
         */
         [httpdicomServer addHandlerForMethod:@"GET"
                                         path:@"/datatables/studies"
                                 requestClass:[GCDWebServerRequest class]
                                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
        {
            NSDictionary *q=request.query;
            NSLog(@"%@",[q description]);
            NSString *session=q[@"session"];
            if (!session || [session isEqualToString:@""]) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'session' parameter"] contentType:@"application/dicom+json"];
            
            NSDictionary *r=Req[session];
            int recordsTotal;
            
            NSString *qPatientID=q[@"columns[3][search][value]"];
            NSString *qPatientName=q[@"columns[4][search][value]"];
            NSString *qStudyDate=q[@"columns[5][search][value]"];
            NSString *qModalitiesInStudy=q[@"columns[6][search][value]"];
            NSString *qStudyDescription=q[@"columns[7][search][value]"];

            NSString *rPatientID=r[@"columns[3][search][value]"];
            NSString *rPatientName=r[@"columns[4][search][value]"];
            NSString *rStudyDate=r[@"columns[5][search][value]"];
            NSString *rModalitiesInStudy=r[@"columns[6][search][value]"];
            NSString *rStduyDescription=r[@"columns[7][search][value]"];
            
            
//same or different context?
            if (
                  !r
                || [q[@"new"]isEqualToString:@"true"]
                || (q[@"username"]    && ![q[@"username"]isEqualToString:r[@"username"]])
                || (q[@"useroid"]     && ![q[@"useroid"]isEqualToString:r[@"useroid"]])
                || (session           && ![session isEqualToString:r[@"session"]])
                || (q[@"org"]         && ![q[@"org"]isEqualToString:r[@"org"]])
                || (q[@"institution"] && ![q[@"institution"]isEqualToString:r[@"institution"]])
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
                ||(    qStudyDate
                   &&![qStudyDate isEqualToString:rStudyDate]
                   &&![rStudyDate isEqualToString:@""]
                   )
                ||(    qModalitiesInStudy
                   &&![qModalitiesInStudy isEqualToString:rModalitiesInStudy]
                   &&![rModalitiesInStudy isEqualToString:@""]
                   )
                ||(    qStudyDescription
                   &&![qStudyDescription isEqualToString:rStduyDescription]
                   &&![rStduyDescription isEqualToString:@""]
                   )
                )
             {
#pragma mark --different context
                 
                 NSLog(@"different context with db:%@",dev0[@"sql"]);
                 NSDictionary *thisSql=sql[dev0[@"sql"]];

                 if (r){
                     //replace previous request of the session.
                     [Req removeObjectForKey:session];
                     [Total removeObjectForKey:session];
                     [Filtered removeObjectForKey:session];
                     [Date removeObjectForKey:session];
                     if(sPatientID[@"session"])[sPatientID removeObjectForKey:session];
                     if(sPatientName[@"session"])[sPatientName removeObjectForKey:session];
                     if(sStudyDate[@"session"])[sStudyDate removeObjectForKey:session];
                     if(sModalitiesInStudy[@"session"])[sModalitiesInStudy removeObjectForKey:session];
                     if(sStudyDescription[@"session"])[sStudyDescription removeObjectForKey:session];

                 }
                 [Req setObject:q forKey:session];
                 [Date setObject:[NSDate date] forKey:session];
                 if(qPatientID)[sPatientID setObject:qPatientID forKey:session];
                 if(qPatientName)[sPatientName setObject:qPatientName forKey:session];
                 if(qStudyDate)[sStudyDate setObject:qStudyDate forKey:session];
                 if(qModalitiesInStudy)[sModalitiesInStudy setObject:qModalitiesInStudy forKey:session];
                 if(qStudyDescription)[sStudyDescription setObject:qStudyDescription forKey:session];
                 
//create the queries
//TODO: add PEP
                 
//WHERE study.rejection_state!=2    (or  1=1)
//following filters use formats like " AND a like 'b'"
                 NSMutableString *studiesWhere=[NSMutableString stringWithString:thisSql[@"studiesWhere"]];

                 if (q[@"search[value]"] && ![q[@"search[value]"] isEqualToString:@""])
                 {
                     //AccessionNumber q[@"search[value]"]
                     [studiesWhere appendString:
                      [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                                       fieldString:thisSql[@"AccessionNumber"]
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
                                           fieldString:thisSql[@"PatientID"]
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
                                           fieldString:(thisSql[@"PatientName"])[0]
                                           valueString:patientNameComponents[0]
                           ]
                          ];
                         
                         if (patientNameCount > 1)
                         {
                             [studiesWhere appendString:
                              [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                               fieldString:(thisSql[@"PatientName"])[1]
                                               valueString:patientNameComponents[1]
                               ]
                              ];

                             if (patientNameCount > 2)
                             {
                                 [studiesWhere appendString:
                                  [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                                   fieldString:(thisSql[@"PatientName"])[2]
                                                   valueString:patientNameComponents[2]
                                   ]
                                  ];

                                 if (patientNameCount > 3)
                                 {
                                     [studiesWhere appendString:
                                      [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                                       fieldString:(thisSql[@"PatientName"])[3]
                                                       valueString:patientNameComponents[3]
                                       ]
                                      ];

                                     if (patientNameCount > 4)
                                     {
                                         [studiesWhere appendString:
                                          [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                                           fieldString:(thisSql[@"PatientName"])[4]
                                                           valueString:patientNameComponents[4]
                                           ]
                                          ];
                                     }
                                 }
                             }
                         }
                     }

                     if(qStudyDate && [qStudyDate length])
                     {
                         [studiesWhere appendFormat:@" AND %@ != '%@'", thisSql[@"StudyDate"], @"*"];
                         //StudyDate _00080020 aaaammdd,-aaaammdd,aaaammdd-,aaaammdd-aaaammdd
                         NSUInteger length=[qStudyDate length];
                         NSRange hyphen=[qStudyDate rangeOfString:@"-"];
                         if (hyphen.length==0)
                         {
                             //no hyphen
                             [studiesWhere appendFormat:@" AND %@ = '%@'", thisSql[@"StudyDate"], qStudyDate];
                         }
                         else if (hyphen.location==0)
                         {
                             //until
                             [studiesWhere appendFormat:@" AND %@ <= '%@'", thisSql[@"StudyDate"], [qStudyDate substringFromIndex:1]];
                         }
                         else if (hyphen.location==length-1)
                         {
                             //since
                             [studiesWhere appendFormat:@" AND %@ >= '%@'", thisSql[@"StudyDate"], [qStudyDate substringToIndex:length-1]];
                         }
                         else
                         {
                             //inbetween
                             [studiesWhere appendFormat:@" AND %@ >= '%@'", thisSql[@"StudyDate"], [qStudyDate substringToIndex:length-hyphen.location-1]];
                             [studiesWhere appendFormat:@" AND %@ <= '%@'", thisSql[@"StudyDate"], [qStudyDate substringFromIndex:hyphen.location+hyphen.length]];
                         }
                     }

                     if(qModalitiesInStudy && [qModalitiesInStudy length] && ![qModalitiesInStudy isEqualToString:@"*"])
                     {
                         //ModalitiesInStudy _00080061 Modalidades (coma separated)
                         [studiesWhere appendFormat:@" AND %@ like '%%%@%%'", thisSql[@"ModalitiesInStudy"], qModalitiesInStudy];
                     }

                     if(qStudyDescription && [qStudyDescription length])
                     {
                         //StudyDescription _00081030 Descripción
                         [studiesWhere appendString:
                          [NSString mysqlEscapedFormat:@" AND %@ like '%@%%'"
                                           fieldString:thisSql[@"StudyDescription"]
                                           valueString:qStudyDescription
                           ]
                          ];
                      }
                 }
                 

                 NSLog(@"SQL: %@",studiesWhere);
                 
//2 execute count
                 NSMutableData *countData=[NSMutableData data];
                 int countResult=task(@"/bin/bash",
                                 @[@"-s"],
                                      [[[thisSql[@"studiesCountProlog"]
                                        stringByAppendingString:studiesWhere]
                                        stringByAppendingString:thisSql[@"studiesCountEpilog"]]
                                        dataUsingEncoding:NSUTF8StringEncoding],
                                 countData
                                 );
                 if (!countResult) [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"%@",@"can not access the db"];

                 NSString *countString=[[NSString alloc]initWithData:countData encoding:NSUTF8StringEncoding];
                 
                 // max (max records filtered para evitar que filtros insuficientes devuelvan casi todos los registros... lo que devolvería un resultado inútil.
                 recordsTotal=[countString intValue];
                 int maxCount=[q[@"max"]intValue];
                 NSLog(@"total:%d, max:%d",recordsTotal,maxCount);
                 if (recordsTotal > maxCount) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:[NSString stringWithFormat:@"you need a narrower filter. The browser table accepts up to %d matches. %d matches were found",maxCount, recordsTotal]] contentType:@"application/dicom+json"];
                 
                 
                 if (!recordsTotal) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"your filer returned zero match"] contentType:@"application/dicom+json"];
                 else
                 {
                     //order is performed later, from mutableDictionary
//3 select
                     NSMutableData *studiesData=[NSMutableData data];
                     int studiesResult=task(@"/bin/bash",
                                          @[@"-s"],
                                          [[[thisSql[@"datatablesStudiesProlog"]
                                            stringByAppendingString:studiesWhere]
                                            stringByAppendingFormat:thisSql[@"datatablesStudiesEpilog"],session,session]
                                            dataUsingEncoding:NSUTF8StringEncoding],
                                          studiesData
                                          );
                     NSMutableArray *studiesArray=[NSJSONSerialization JSONObjectWithData:studiesData options:NSJSONReadingMutableContainers error:nil];

                     [Total setObject:studiesArray forKey:session];
                     [Filtered setObject:[studiesArray mutableCopy] forKey:session];
                 }
             }//end diferent context
            else
            {

#pragma mark --same context
                
                recordsTotal=[Total[session]count];
                NSLog(@"same context recordsTotal: %d ",recordsTotal);

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
                        PatientIDRegex=[NSRegularExpression regularExpressionWithPattern:[NSString regexDicomString:qPatientID withFormat:@"datatables\\/patients\\?PatientID=%@.*"] options:0 error:NULL];
                        [sPatientID removeObjectForKey:session];
                        [sPatientID setObject:qPatientID forKey:session];
                    }
                    
                    NSRegularExpression *PatientNameRegex=nil;
                    if(qPatientName && ![qPatientName isEqualToString:sPatientName[session]])
                    {
                        toBeFiltered=true;
                        PatientNameRegex=[NSRegularExpression regularExpressionWithPattern:[NSString regexDicomString:qPatientName withFormat:@"%@.*"] options:NSRegularExpressionCaseInsensitive error:NULL];
                        [sPatientName removeObjectForKey:session];
                        [sPatientName setObject:qPatientName forKey:session];
                    }
                    
                    NSString *StudyDate;
                    NSString *until;
                    NSString *since;
                    if(qStudyDate && ![qStudyDate isEqualToString:sStudyDate[session]])
                    {
                        toBeFiltered=true;

                        //StudyDate _00080020 aaaammdd,-aaaammdd,aaaammdd-,aaaammdd-aaaammdd
                        NSUInteger length=[qStudyDate length];
                        NSRange hyphen=[qStudyDate rangeOfString:@"-"];
                        if (hyphen.length==0)
                        {
                            //no hyphen
                            StudyDate=qStudyDate;
                        }
                        else if (hyphen.location==0)
                        {
                            //until
                            until=[qStudyDate substringFromIndex:1];
                        }
                        else if (hyphen.location==length-1)
                        {
                            //since
                            since=[qStudyDate substringToIndex:length-2];
                        }
                        else
                        {
                            //inbetween
                            //until
                            until=[qStudyDate substringFromIndex:hyphen.location+hyphen.length];
                            //since
                            since=[qStudyDate substringToIndex:length-hyphen.location-1];
                        }
                        [sStudyDate removeObjectForKey:session];
                        [sStudyDate setObject:qStudyDate forKey:session];

                    }
                    
                    NSString *newModalitiesInStudy=nil;
                    if(qModalitiesInStudy && ![qModalitiesInStudy isEqualToString:sModalitiesInStudy[session]])
                    {
                        toBeFiltered=true;
                        newModalitiesInStudy=qModalitiesInStudy;
                        [sModalitiesInStudy removeObjectForKey:session];
                        [sModalitiesInStudy setObject:qModalitiesInStudy forKey:session];
                    }

                    
                    NSRegularExpression *StudyDescriptionRegex=nil;
                    if(qStudyDescription  && ![qStudyDescription isEqualToString:sStudyDescription[session]])
                    {
                        toBeFiltered=true;
                        StudyDescriptionRegex=[NSRegularExpression regularExpressionWithPattern:[NSString regexDicomString:qStudyDescription withFormat:@"%@.*"] options:NSRegularExpressionCaseInsensitive error:NULL];
                        [sStudyDescription removeObjectForKey:session];
                        [sStudyDescription setObject:qStudyDescription forKey:session];
                    }

                    if(toBeFiltered)
                    {
                        //filter from BTotal copy
                        [Filtered removeObjectForKey:session];
                        [Filtered setObject:[Total[session] mutableCopy] forKey:session];
                        
                        //create compound predicate
                        NSPredicate *compoundPredicate = [NSPredicate predicateWithBlock:^BOOL(NSArray *BRow, NSDictionary *bindings) {
                            if (PatientIDRegex)
                            {
                                if (![PatientIDRegex numberOfMatchesInString:BRow[3] options:0 range:NSMakeRange(0,[BRow[3] length])]) return false;
                            }
                            if (PatientNameRegex)
                            {
                                if (![PatientNameRegex numberOfMatchesInString:BRow[4] options:0 range:NSMakeRange(0,[BRow[4] length])]) return false;
                            }
                            if (StudyDate)
                            {
                                if (![StudyDate isEqualToString:BRow[5]]) return false;
                            }
                            if (until)
                            {
                                if ([until compare:BRow[5]]==NSOrderedDescending) return false;
                            }
                            if (since)
                            {
                                if ([since compare:BRow[5]]==NSOrderedAscending) return false;
                            }
                            if (newModalitiesInStudy)
                            {
                                if (![BRow[6] containsString:newModalitiesInStudy]) return false;
                            }
                            if (StudyDescriptionRegex)
                            {
                                if (![StudyDescriptionRegex numberOfMatchesInString:BRow[7] options:0 range:NSMakeRange(0,[BRow[7] length])]) return false;
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
                NSLog(@"ordering with %@, %@",q[@"order[0][column]"],q[@"order[0][dir]"]);
                
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
            [resp setObject:[NSNumber numberWithInt:recordsFiltered] forKey:@"recordsFiltered"];
            if (!recordsFiltered) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"your filer returned zero match"] contentType:@"application/dicom+json"];
            else
            {
                //start y length
                long ps=[q[@"start"]intValue];
                long pl=[q[@"length"]intValue];
                NSLog(@"paging desired (start=[%ld],filas=[%ld],last=[%d])",ps,pl,recordsFiltered-1);
                if (ps < 0) ps=0;
                if (ps > recordsFiltered-1) ps=0;
                if (ps+pl+1 > recordsFiltered) pl=recordsFiltered-ps;
                NSLog(@"paging applied (start=[%ld],filas=[%ld],last=[%d])",ps,pl,recordsFiltered-1);
                NSArray *page=[Filtered[session] subarrayWithRange:NSMakeRange(ps,pl)];
                if (!page)page=@[];
                [resp setObject:page forKey:@"data"];
            }
            
             return [GCDWebServerDataResponse
                     responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:resp]
                     contentType:@"application/dicom+json"
                     ];
         }
         ];

#pragma mark datatables/patient
        /*
         ventana emergente con todos los estudios del paciente
         "datatables/patient?PatientID=33333333&IssuerOfPatientID.UniversalEntityID=NULL&session=1"
         */
        [httpdicomServer addHandlerForMethod:@"GET"
                                        path:@"/datatables/patient"
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSDictionary *q=request.query;
             NSLog(@"%@",[q description]);
             
             NSString *session=q[@"session"];
             if (!session || [session isEqualToString:@""]) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'session' parameter"] contentType:@"application/dicom+json"];
             
             if (!q[@"PatientID"]) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"studies of patient query without required 'patientID' parameter"] contentType:@"application/dicom+json"];
             
             //WHERE study.rejection_state!=2    (or  1=1)
             //following filters use formats like " AND a like 'b'"
             NSDictionary *thisSql=sql[dev0[@"sql"]];
             NSMutableString *studiesWhere=[NSMutableString stringWithString:thisSql[@"studiesWhere"]];
             [studiesWhere appendString:
              [NSString mysqlEscapedFormat:@" AND %@ like '%@'"
                               fieldString:thisSql[@"PatientID"]
                               valueString:q[@"PatientID"]
               ]
              ];
             NSLog(@"SQL: %@",studiesWhere);
             
             NSMutableData *studiesData=[NSMutableData data];
             int studiesResult=task(@"/bin/bash",
                                    @[@"-s"],
                                    [[[thisSql[@"datatablesStudiesProlog"]
                                       stringByAppendingString:studiesWhere]
                                      stringByAppendingFormat:thisSql[@"datatablesStudiesEpilog"],session,session]
                                     dataUsingEncoding:NSUTF8StringEncoding],
                                    studiesData
                                    );
             NSMutableArray *studiesArray=[NSJSONSerialization JSONObjectWithData:studiesData options:NSJSONReadingMutableContainers error:nil];
             
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
             return [GCDWebServerDataResponse
                     responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:resp]
                     contentType:@"application/dicom+json"
                     ];
         }
         ];

        
#pragma mark datatables/series
        //"datatables/series?AccessionNumber=22&IssuerOfAccessionNumber.UniversalEntityID=NULL&StudyIUID=2.16.858.2.10000675.72769.20160411084701.1.100&session=1"
        [httpdicomServer addHandlerForMethod:@"GET"
                                        path:@"/datatables/series"
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSDictionary *q=request.query;
             NSString *session=q[@"session"];
             if (!session || [session isEqualToString:@""]) return [GCDWebServerDataResponse responseWithData:[NSData jsonpCallback:q[@"callback"] forDraw:q[@"draw"] withErrorString:@"query without required 'session' parameter"] contentType:@"application/dicom+json"];
             
             NSDictionary *thisSql=sql[dev0[@"sql"]];
             NSString *where=[NSString stringWithFormat:@"%@ AND %@='%@'",
                              thisSql[@"seriesWhere"],
                              thisSql[@"StudyInstanceUID"],
                              q[@"StudyIUID"]
                              ];
             NSLog(@"SQL: %@",where);

             NSMutableData *seriesData=[NSMutableData data];
             int seriesResult=task(@"/bin/bash",
                                    @[@"-s"],
                                    [[[thisSql[@"seriesProlog"]
                                       stringByAppendingString:where]
                                      stringByAppendingFormat:thisSql[@"seriesEpilog"],session,session]
                                     dataUsingEncoding:NSUTF8StringEncoding],
                                    seriesData
                                    );
             NSMutableArray *seriesArray=[NSJSONSerialization JSONObjectWithData:seriesData options:NSJSONReadingMutableContainers error:nil];
             NSLog(@"series array:%@",[seriesArray description]);

             NSMutableDictionary *resp = [NSMutableDictionary dictionary];
             if (q[@"draw"])[resp setObject:q[@"draw"] forKey:@"draw"];
             NSNumber *count=[NSNumber numberWithUnsignedInteger:[seriesArray count]];
             [resp setObject:count forKey:@"recordsTotal"];
             [resp setObject:count forKey:@"recordsFiltered"];
             [resp setObject:seriesArray forKey:@"data"];
             return [GCDWebServerDataResponse
                     responseWithData:[NSData jsonpCallback:q[@"callback"]withDictionary:resp]
                     contentType:@"application/dicom+json"
                     ];
         }
         ];

        
//#pragma mark zipped wadoRS studies series instances
//zipped/studies/{StudyInstanceUID}
//zipped/studies/{StudyInstanceUID}/series/{SeriesInstanceUID}
//zipped/studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}

        
#pragma mark wadors
//studies/{StudyInstanceUID}
//studies/{StudyInstanceUID}/series/{SeriesInstanceUID}
//studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}
//Accept: multipart/related;type="application/dicom"
        NSRegularExpression *wadorsregex = [NSRegularExpression regularExpressionWithPattern:@"studies/" options:NSRegularExpressionCaseInsensitive error:NULL];

        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:wadorsregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSString *wadorsString=[[dev0 objectForKey:@"wadors"] stringByAppendingString:request.URL.path];
             GWS_LOG_INFO(@"dev0 wadors: %@",wadorsString);
             
             //request, response and error
             NSMutableURLRequest *wadorsRequest=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:wadorsString] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];
             //https://developer.apple.com/reference/foundation/nsurlrequestcachepolicy?language=objc
             [wadorsRequest setHTTPMethod:@"GET"];
             [wadorsRequest setValue:@"multipart/related;type=application/dicom" forHTTPHeaderField:@"Accept"];
             NSHTTPURLResponse *response=nil;
             //URL properties: expectedContentLength, MIMEType, textEncodingName
             //HTTP properties: statusCode, allHeaderFields
             NSError *error=nil;
             
             
             NSData *data=[NSURLConnection sendSynchronousRequest:wadorsRequest
                                                returningResponse:&response
                                                            error:&error];

             if ((response.statusCode==200) && [data length]) return [GCDWebServerDataResponse
                     responseWithData:data
                     contentType:@"multipart/related;type=application/dicom"
                     ];

             return [GCDWebServerErrorResponse responseWithClientError:404 message:@"%@",[error description]];
         }
         ];

        
#pragma mark applicable
///applicable/DOC/EncapsulatedDocument/CDA?AccessionNumber={AccessionNumber}
///applicable/DOC/EncapsulatedDocument?AccessionNumber={AccessionNumber}
///applicable/DOC?AccessionNumber={AccessionNumber}
///applicable/OT/EncapsulatedDocument?AccessionNumber={AccessionNumber}
///applicable/OT?AccessionNumber={AccessionNumber}
        
        NSRegularExpression *encapsulatedregex = [NSRegularExpression regularExpressionWithPattern:@"^/applicable" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:encapsulatedregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             //AccessionNumber
             NSString *q=request.URL.query;
             if (q.length>32 || ![q hasPrefix:@"AccessionNumber="]) [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"dev0 /applicable without parameter AccessionNumber"
              ];
             NSString *accessionNumber=[q substringWithRange:NSMakeRange(16,q.length-16)];
             
             //Modality
             NSString *p=request.URL.path;
             NSString *modalityPrefix=[p substringWithRange:NSMakeRange(12,2)];
             if (!([modalityPrefix isEqualToString:@"DO"] || [modalityPrefix isEqualToString:@"OT"])) [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"dev0 /applicable only for modalities DO[C] or OT"];
             NSString *modality;
             if ([modalityPrefix isEqualToString:@"DO"]) modality=@"DOC";
             else modality=modalityPrefix;
            
             
             //instances?AccessionNumber={AccessionNumber}&Modality=DOC
             NSString *qidoString=[NSString stringWithFormat:@"%@/instances?AccessionNumber=%@&Modality=%@",
                                [dev0 objectForKey:@"qido"],
                                accessionNumber,
                                modality];
             GWS_LOG_INFO(@"dev0 applicable qido %@",qidoString);
             NSData *instanceQidoData=[NSData dataWithContentsOfURL:
                                   [NSURL URLWithString:qidoString]];

             
             //applicable, latest doc
             //6.7.1.2.3.2 JSON Results
             //If there are no matching results,the JSON message is empty.
             if (!instanceQidoData || ![instanceQidoData length]) [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"dev0 /applicable not found"];
             
             NSArray *instanceArray=[NSJSONSerialization JSONObjectWithData:instanceQidoData options:0 error:nil];
             NSUInteger instanceArrayCount=[instanceArray count];
             if (instanceArrayCount==0) [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"dev0 /applicable not found"];
             
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

             if ([p rangeOfString:@"EncapsulatedDocument"].location!=NSNotFound)
             {
                 //wadors returns bytstream with 00420010
                 NSString *wadoRsString=(((instanceArray[index])[@"00081190"])[@"Value"])[0];
                 GWS_LOG_INFO(@"dev0 applicable wadors %@",wadoRsString);
                 
                 NSData *applicableData=[NSData dataWithContentsOfURL:[NSURL URLWithString:wadoRsString]];
                 if (!applicableData || ![applicableData length]) return [GCDWebServerErrorResponse responseWithClientError:404 message:@"dev0 applicable %@ notFound",request.URL.path];

                 NSUInteger applicableDataLength=[applicableData length];

                 NSUInteger valueLocation;
                 //between "Content-Type: " and "\r\n"
                 NSRange ctRange  = [applicableData rangeOfData:contentType options:0 range:NSMakeRange(0, applicableDataLength)];
                 valueLocation=ctRange.location+ctRange.length;
                 NSRange rnRange  = [applicableData rangeOfData:rn options:0 range:NSMakeRange(valueLocation, applicableDataLength-valueLocation)];
                 NSData *contentTypeData=[applicableData subdataWithRange:NSMakeRange(valueLocation,rnRange.location-valueLocation)];
                 NSString *ctString=[[NSString alloc]initWithData:contentTypeData encoding:NSUTF8StringEncoding];
                 GWS_LOG_INFO(@"%@",ctString);

                 
                 //between "\r\n\r\n" and "\r\n--"
                 NSRange rnrnRange=[applicableData rangeOfData:rnrn options:0 range:NSMakeRange(0, applicableDataLength)];
                 valueLocation=rnrnRange.location+rnrnRange.length;
                 NSRange rnhhRange=[applicableData rangeOfData:rnhh options:0 range:NSMakeRange(valueLocation, applicableDataLength-valueLocation)];
                 
                 //encapsulatedData
                 NSData *encapsulatedData=[applicableData subdataWithRange:NSMakeRange(valueLocation,rnhhRange.location-valueLocation - 1 - ([[applicableData subdataWithRange:NSMakeRange(rnhhRange.location-2,2)] isEqualToData:rn] * 2))];
                     
                 if ([p rangeOfString:@"CDA"].location != NSNotFound)
                 {
                     GWS_LOG_INFO(@"CDA");
                     NSRange CDAOpeningTagRange=[encapsulatedData rangeOfData:CDAOpeningTag options:0 range:NSMakeRange(0, encapsulatedData.length)];
                     if (CDAOpeningTagRange.location != NSNotFound)
                     {
                         NSRange CDAClosingTagRange=[encapsulatedData rangeOfData:CDAClosingTag options:0 range:NSMakeRange(0, encapsulatedData.length)];
                         NSData *cdaData=[encapsulatedData subdataWithRange:NSMakeRange(CDAOpeningTagRange.location, CDAClosingTagRange.location+CDAClosingTagRange.length-CDAOpeningTagRange.location)];
                         return [GCDWebServerDataResponse
                                 responseWithData:cdaData
                                 contentType:ctString];
                     }
                 }
                 
                 return [GCDWebServerDataResponse
                        responseWithData:encapsulatedData
                        contentType:ctString];
             }
             else
             {
                 NSString *wadouriString=[NSString stringWithFormat:
                  @"%@?requestType=WADO&studyUID=%@&seriesUID=%@&objectUID=%@&contentType=application%%2Fdicom",
                      [dev0 objectForKey:@"wadouri"],
                      (((instanceArray[index])[@"0020000D"])[@"Value"])[0],
                      (((instanceArray[index])[@"0020000E"])[@"Value"])[0],
                      (((instanceArray[index])[@"00080018"])[@"Value"])[0]];

                 //wado-uri return application/dicom
                 NSData *responseData=[NSData dataWithContentsOfURL:[NSURL URLWithString:wadouriString]];
                 if (!responseData) return
                 [GCDWebServerErrorResponse
                  responseWithClientError:kGCDWebServerHTTPStatusCode_FailedDependency
                  message:@"dev0 wadouri: %@",wadouriString
                  ];
                 
                 if (![responseData length]) return
                 [GCDWebServerErrorResponse
                  responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound
                  message:@"dev0 wadouri: %@",wadouriString
                  ];
                 return [GCDWebServerDataResponse
                         responseWithData:responseData
                         contentType:@"application/dicom"
                         ];
                 
             }
         }
         ];

        

#pragma mark metadata
//studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/metadata

        NSRegularExpression *metadataregex = [NSRegularExpression regularExpressionWithPattern:@"/metadata$" options:NSRegularExpressionCaseInsensitive error:NULL];

        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:metadataregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             GWS_LOG_INFO(@"dev0 metadata: %@",request.URL.path);
             NSString *metadataString=[NSString stringWithFormat:
                                       @"%@%@",
                                       [dev0 objectForKey:@"wadors"],
                                       request.URL.path
                                       ];

             NSData *responseData=[NSData dataWithContentsOfURL:[NSURL URLWithString:metadataString]];
             if (!responseData) return
             [GCDWebServerErrorResponse
              responseWithClientError:kGCDWebServerHTTPStatusCode_FailedDependency
              message:@"dev0 metadata: %@",metadataString
              ];
             
             if (![responseData length]) return
             [GCDWebServerErrorResponse
              responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound
              message:@"dev0 metadata: %@",metadataString
              ];
             return [GCDWebServerDataResponse
                     responseWithData:responseData
                       contentType:@"application/dicom+json"
                     ];
         }
         ];
#pragma mark dicom wado-uri
        NSRegularExpression *wadouriregex = [NSRegularExpression regularExpressionWithPattern:@"^/$" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:wadouriregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSString *wadouriString=[NSString stringWithFormat:@"%@?%@",[dev0 objectForKey:@"wadouri"],request.URL.query];
             //no se agrega ningún control para no enlentecer
             //podría optimizarse con creación asíncrona de la data
             //paquetes entran y salen sin esperar el fin de la entrada...
             GWS_LOG_INFO(@"dev0 wadouri: %@",wadouriString);
             NSData *responseData=[NSData dataWithContentsOfURL:[NSURL URLWithString:wadouriString]];
             if (!responseData) return
                 [GCDWebServerErrorResponse
                  responseWithClientError:kGCDWebServerHTTPStatusCode_FailedDependency
                  message:@"dev0 wadouri: %@",wadouriString
                  ];
             
             if (![responseData length]) return
                 [GCDWebServerErrorResponse
                  responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound
                  message:@"dev0 wadouri: %@",wadouriString
                  ];
             return [GCDWebServerDataResponse
                     responseWithData:responseData
                     contentType:@"application/dicom"
                     ];
         }
         ];
        

#pragma mark -
#pragma mark _____________LAN dicom_____________
//#pragma mark wado-uri
        /*
        NSRegularExpression *dicomwadoregex = [NSRegularExpression regularExpressionWithPattern:@"^/.*" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:dicomwadoregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
                                    NSURL *requestURL=request.URL;
                                    NSString *bSlash=requestURL.baseURL.absoluteString;
                                    NSString *b=[bSlash substringToIndex:[bSlash length]-1];
                                    NSString *p=requestURL.path;
                                    NSString *q=requestURL.query;
                                    GWS_LOG_INFO(@"no handler for:(%@) %@%@?%@",request.method,b,p,q);
                                    return [GCDWebServerDataResponse responseWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://opendicom.com"]] contentType:@"text/html"];
                                }
         ];
         */
/*
#pragma mark studies
        //studies
        
        NSRegularExpression *dicomstudiesqidoregex = [NSRegularExpression regularExpressionWithPattern:@"studies" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark series
        //series
        
        NSRegularExpression *dicomseriesqidoregex = [NSRegularExpression regularExpressionWithPattern:@"series" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark instances
        //instances
        
        NSRegularExpression *dicominstancesqidoregex = [NSRegularExpression regularExpressionWithPattern:@"instances" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark studies/
        //studies/{StudyInstanceUID}
        
        NSRegularExpression *dicomstudieswadoregex = [NSRegularExpression regularExpressionWithPattern:@"studies/" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        
#pragma mark series/
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}
        
        NSRegularExpression *dicomserieswadoregex = [NSRegularExpression regularExpressionWithPattern:@"/series/" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark cda
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/cda
        
        NSRegularExpression *dicomcdaregex = [NSRegularExpression regularExpressionWithPattern:@"/cda$" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark encapsulated
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/encapsulated
        
        NSRegularExpression *dicomencapsulatedregex = [NSRegularExpression regularExpressionWithPattern:@"/encapsulated$" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark metadata
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/metadata
        
        NSRegularExpression *diocmmetadataregex = [NSRegularExpression regularExpressionWithPattern:@"/metadata$" options:NSRegularExpressionCaseInsensitive error:NULL];
 */
#pragma mark -
#pragma mark _____________WAN dicomweb_____________
//#pragma mark wado-uri
        
        /*
        NSRegularExpression *remotowadoregex = [NSRegularExpression regularExpressionWithPattern:@"^/.*" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:remotowadoregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
                                    NSURL *requestURL=request.URL;
                                    NSString *bSlash=requestURL.baseURL.absoluteString;
                                    NSString *b=[bSlash substringToIndex:[bSlash length]-1];
                                    NSString *p=requestURL.path;
                                    NSString *q=requestURL.query;
                                    GWS_LOG_INFO(@"no handler for:(%@) %@%@?%@",request.method,b,p,q);
                                    return [GCDWebServerDataResponse responseWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://opendicom.com"]] contentType:@"text/html"];
                                }
         ];
         */
/*
#pragma mark studies
        //studies
        
        NSRegularExpression *remotostudiesqidoregex = [NSRegularExpression regularExpressionWithPattern:@"studies" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark series
        //series
        
        NSRegularExpression *remotoseriesqidoregex = [NSRegularExpression regularExpressionWithPattern:@"series" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark instances
        //instances
        
        NSRegularExpression *remotoinstancesqidoregex = [NSRegularExpression regularExpressionWithPattern:@"instances" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark studies/
        //studies/{StudyInstanceUID}
        
        NSRegularExpression *remotostudieswadoregex = [NSRegularExpression regularExpressionWithPattern:@"studies/" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        
#pragma mark series/
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}
        
        NSRegularExpression *remotoserieswadoregex = [NSRegularExpression regularExpressionWithPattern:@"/series/" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark cda
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/cda
        
        NSRegularExpression *remotocdaregex = [NSRegularExpression regularExpressionWithPattern:@"/cda$" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark encapsulated
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/encapsulated
        
        NSRegularExpression *remotoencapsulatedregex = [NSRegularExpression regularExpressionWithPattern:@"/encapsulated$" options:NSRegularExpressionCaseInsensitive error:NULL];
        
#pragma mark metadata
        //studies/{StudyInstanceUID}/series/{SeriesInstanceUID}/instances/{SOPInstanceUID}/metadata
        
        NSRegularExpression *remotometadataregex = [NSRegularExpression regularExpressionWithPattern:@"/metadata$" options:NSRegularExpressionCaseInsensitive error:NULL];
*/

#pragma mark -
#pragma mark _____________IID_____________
#pragma mark    /bir/weasis
//-----------------------------------------------------------------
// http://{localpcs}/weasis/
//-----------------------------------------------------------------
        [httpdicomServer addGETHandlerForBasePath:@"/bir/weasis/" directoryPath:[resources stringByAppendingPathComponent:@"weasis/"] indexFilename:nil cacheAge:3600 allowRangeRequests:YES];
        
        
#pragma mark /bir/weasis/bundle
//-----------------------------------------------------------------
// http://{localpcs}/weasis/bundle/
//-----------------------------------------------------------------
        [httpdicomServer addGETHandlerForBasePath:@"/bir/weasis/bundle/" directoryPath:[resources stringByAppendingPathComponent:@"weasis/bundle/"] indexFilename:nil cacheAge:3600 allowRangeRequests:YES];

        
#pragma mark IHEInvokeImageDisplay
//-----------------------------------------------------------------------------------------------------------------------------
// IHEInvokeImageDisplay?requestType=STUDY&accessionNumber=1&viewerType=IHE_BIR&diagnosticQuality=true&keyImagesOnly=false&custodianUID=1.2
//-----------------------------------------------------------------------------------------------------------------------------
        
        [httpdicomServer addHandlerForMethod:@"GET"
                                  path:@"/IHEInvokeImageDisplay"
                               requestClass:[GCDWebServerRequest class]
                               processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSDictionary *q=request.query;

             //(1) b= html5dicomURL
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             GWS_LOG_INFO(@"%@%@?%@",b,p,requestURL.query);
             
             
             //(2) accept requestType STUDY / SERIES only
             NSString *requestType=q[@"requestType"];
             if (
                   !requestType
                 ||!
                    (  [requestType isEqualToString:@"STUDY"]
                     ||[requestType isEqualToString:@"SERIES"]
                     )
                 ) return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"missing requestType param in %@%@?%@",b,p,requestURL.query]];
             
             //find URI of custodianUID
             NSString *custodianURI;
             if (q[@"custodianUID"]) custodianURI=(devs[q[@"custodianUID"]])[@"pcsurl"];
             else custodianURI=@"";
             
             //redirect to specific manifest
             NSMutableString *manifest=[NSMutableString string];
             
             NSString *viewerType=q[@"viewerType"];
             if (  !viewerType
                 || [viewerType isEqualToString:@"IHE_BIR"]
                 || [viewerType isEqualToString:@"weasis"]
                 )
             {
//weasis
                 [manifest appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r"];
                 [manifest appendFormat:@"<wado_query wadoURL=\"%@\" requireOnlySOPInstanceUID=\"false\" additionnalParameters=\"%@\">\r",
                  b,
                  (devs[q[@"custodianUID"]])[@"wadoadditionalparameters"]
                  ];

                 if ([requestType isEqualToString:@"STUDY"])
                 {
                     NSString *manifestWeasisStudiesURI;
                     if (q[@"accessionNumber"]) manifestWeasisStudiesURI=[NSString stringWithFormat:@"%@/bir/manifest/weasis/studies?AccessionNumber=%@",custodianURI,q[@"accessionNumber"]];
                     else if (q[@"studyUID"]) manifestWeasisStudiesURI=[NSString stringWithFormat:@"%@/bir/manifest/weasis/studies?StudyInstanceUID=%@",custodianURI,q[@"studyUID"]];
                     else return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];

                      [manifest appendFormat:@"%@\r</wado_query>\r",[NSString stringWithContentsOfURL:[NSURL URLWithString:manifestWeasisStudiesURI] encoding:NSUTF8StringEncoding error:nil]];
                      //GWS_LOG_INFO(@"%@",manifest);
                 }
                 else
                 {
                     //SERIES
                 }
                 GCDWebServerDataResponse *response=[GCDWebServerDataResponse responseWithData:[[[LFCGzipUtility gzipData:[manifest dataUsingEncoding:NSUTF8StringEncoding]] base64EncodedStringWithOptions:0]dataUsingEncoding:NSUTF8StringEncoding] contentType:@"application/x-gzip"];
                 [response setValue:@"Base64" forAdditionalHeader:@"Content-Transfer-Encoding"];//https://tools.ietf.org/html/rfc2045
                 return response;
             }
             else if ([viewerType isEqualToString:@"OsiriX"])
             {
//OsiriX
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
                     else return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                     
                 }
                 else
                 {
                     //SERIES
                 }
             }
             else if ([viewerType isEqualToString:@"cornerstone"])
             {
//cornerstone
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
                     else return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                     
                 }
                 else
                 {
                     //SERIES
                 }
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
                     else return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                     
                 }
                 else
                 {
                     //SERIES
                 }
             }
             else if ([viewerType isEqualToString:@"download"])
             {
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
                     else return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"requestType=STUDY requires param accessionNumber or studyUID in %@%@?%@",b,p,requestURL.query]];
                     
                 }
                 else
                 {
                     //SERIES
                 }
             }
             else return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"unknown viewerType in %@%@?%@",b,p,requestURL.query]];
             
             {
                 /*
                 if (error)
                 {
                     GWS_LOG_WARNING(@"%@",[error description]);
                     return [GCDWebServerDataResponse responseWithText:[NSString stringWithFormat:@"%@",[error description]]];
                 }
                 if ([xmlData length]>0)
                 {
                     BOOL seriesFetched=false;
                     //get study and series UID
                     NSXMLDocument *xmlDocument=[[NSXMLDocument alloc]initWithData:xmlData options:0 error:nil];
                     NSArray *studyArray = [xmlDocument nodesForXPath:@"wado_query/Patient/Study" error:NULL];
                     for (id studyNode in studyArray)
                     {
                         NSArray *studyInstanceUIDarray = [studyNode nodesForXPath:@"@StudyInstanceUID" error:NULL];
                         NSString *studyInstanceUID = [[studyInstanceUIDarray objectAtIndex:0]stringValue];
                         
                         NSArray *seriesArray = [studyNode nodesForXPath:@"Series" error:NULL];
#pragma mark download series and forward them to dcm4chee
                         //dispach download of series from OsiriX
                         for (id seriesNode in seriesArray)
                         {
                             seriesFetched=true;
                             NSArray *seriesInstanceUIDarray = [seriesNode nodesForXPath:@"@SeriesInstanceUID" error:NULL];
                             NSString *seriesInstanceUID = [[seriesInstanceUIDarray objectAtIndex:0]stringValue];
                             
                             NSString *retrieveSeries=[NSString stringWithFormat:@"%@/%@/studies/%@/series/%@",
                                                       [remote objectForKey:@"wadoRS"],
                                                       [remote objectForKey:@"aet"],
                                                       studyInstanceUID,
                                                       seriesInstanceUID
                                                       ];
                             NSString *seriesPath=[[auditPath stringByAppendingPathComponent:seriesInstanceUID] stringByAppendingPathComponent:[dicomDTFormatter stringFromDate:[NSDate date]]];
                             if(![fileManager fileExistsAtPath:seriesPath])
                             {
                                 NSLog(@"wado-rs series: %@",seriesPath);
                                 //first processing of solicitud
                                 if(![fileManager createDirectoryAtPath:seriesPath withIntermediateDirectories:YES attributes:nil error:nil])
                                     NSLog(@"ERROR could not create folder");
                                 else
                                 {
                                     NSData *downloaded=[NSData dataWithContentsOfURL:[NSURL URLWithString:retrieveSeries]];
                                     if (downloaded && [downloaded length]>0)
                                     {
                                         //[downloaded writeToFile:[seriesPath stringByAppendingPathComponent:@"downloaded.zip"] atomically:NO];
                                         
                                         //unzip
                                         NSError *error=nil;
                                         ZZArchive *archive = [ZZArchive archiveWithData:downloaded];
                                         NSUInteger entriesCount=archive.entries.count;
                                         NSLog(@"unzipped objects %lu",(unsigned long)entriesCount);
                                         
                                         unsigned long counter=0;
                                         BOOL oneOrMoreUnzipped=false;
                                         for (ZZArchiveEntry *entry in archive.entries)
                                         {
                                             NSData *unzipped= [entry newDataWithError:&error];
                                             if (error!=nil) NSLog(@"ERROR could NOT unzip\r%@",[error description]);
                                             else oneOrMoreUnzipped|=[unzipped writeToFile:[NSString stringWithFormat:@"%@/%lu.dcm",seriesPath,counter++] atomically:NO];
                                         }
                                         if (oneOrMoreUnzipped)
                                         {
                                             NSMutableArray *argsSeries=[NSMutableArray arrayWithArray:storescuArgs];
                                             [argsSeries addObject:seriesPath];

                                             NSMutableData *stdoutData = [NSMutableData data];
                                             task(
                                                  storescu,
                                                  argsSeries,
                                                  [NSData data],
                                                  stdoutData
                                                  );
                                             [stdoutData writeToFile:[seriesPath stringByAppendingPathComponent:@"stdout+stderr.log"] atomically:NO];
                                         }
                                     }
                                 }
                             }
                         }
                     }
                  
                     if (seriesFetched)
                     {
                         //create jnlp
                         NSString *xmlString=[[NSString alloc]initWithData:xmlData encoding:NSUTF8StringEncoding];
                         NSString *localizedXmlString=[NSString stringWithFormat:xmlString,[dev0 objectForKey:@"wadoURL"],[dev0 objectForKey:@"wadoAdditionnalParameters"]];
                         NSData *gzipped=[LFCGzipUtility gzipData:[localizedXmlString dataUsingEncoding:NSUTF8StringEncoding]];

                         return [GCDWebServerDataResponse responseWithData:[[NSString stringWithFormat:jnlp,[gzipped base64EncodedStringWithOptions:0]] dataUsingEncoding:NSUTF8StringEncoding] contentType:@"application/x-java-jnlp-file"];//application/x-gzip"];//
                     }
                     GWS_LOG_WARNING(@"no series");
                     return [GCDWebServerDataResponse responseWithText:@"no series"];
                 }
                 else
                 {
                     GWS_LOG_WARNING(@"no series");
                     return [GCDWebServerDataResponse responseWithText:@"no series"];
                 }
                  */
            }
             GWS_LOG_WARNING(@"incorrect syntax for request /bir/study");
             return [GCDWebServerDataResponse responseWithText:@"incorrect syntax for request /IHEInvokeImageDisplay"];
         }
         ];
        
        
#pragma mark /bir/manifest/weasis/studies?
        //------------------------------------------------
        // http://{remotepcs}/bir/manifest/weasis/studies?
        //------------------------------------------------
        
        NSRegularExpression *mwstudiesregex = [NSRegularExpression regularExpressionWithPattern:@"^/bir/manifest/weasis/studies" options:NSRegularExpressionCaseInsensitive error:NULL];
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:mwstudiesregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             //request parts logging
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             NSString *q=requestURL.query;
             
             NSDictionary *thisSql=sql[dev0[@"sql"]];
             NSString *sqlString;
             NSString *AccessionNumber=request.query[@"AccessionNumber"];
             if (AccessionNumber)sqlString=[NSString stringWithFormat:thisSql[@"manifestWeasisStudyAccessionNumber"],AccessionNumber];
             else
             {
                 NSString *StudyInstanceUID=request.query[@"StudyInstanceUID"];
                 if (StudyInstanceUID)sqlString=[NSString stringWithFormat:thisSql[@"manifestWeasisStudyStudyInstanceUID"],StudyInstanceUID];
                 else return [GCDWebServerErrorResponse responseWithClientError:404 message:
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
                     //NSLog(@"<Patient PatientName=\"%@\" PatientID=\"%@\" IssuerOfPatientID=\"%@\" PatientBirthDate=\"%@\" PatientSex=\"%@\">\r",patientAttrs[0],patientAttrs[1],patientAttrs[2],patientAttrs[3],patientAttrs[4]);
                     
                     for (NSArray *studyInstance in studyArray)
                     {
                         if (  [studyInstance[1]isEqualToString:patientAttrs[1]]
                             &&[studyInstance[2]isEqualToString:patientAttrs[2]]
                            )
                         {
                            //each study of this patient
                             [weasisManifest appendFormat:
                              @"<Study SpecificCharacterSet=\"UTF-8\" StudyInstanceUID=\"%@\" AccessionNumber=\"%@\" IssuerOfAccessionNumber=\"%@\" RetrieveAETitle=\"%@\" StudyID=\"%@\" StudyDescription=\"%@\" StudyDate=\"%@\" StudyTime=\"%@\" WadorsURI=\"/studies/%@\">\r",
                              studyInstance[5],
                              studyInstance[6],
                              studyInstance[7],
                              studyInstance[8],
                              studyInstance[9],
                              studyInstance[10],
                              studyInstance[11],
                              studyInstance[12],
                              studyInstance[5]
                              ];
                             
                             //series
                             NSMutableData *seriesData=[NSMutableData data];
                             int seriesResult=task(@"/bin/bash",
                                                    @[@"-s"],
                                                    [[NSString stringWithFormat:thisSql[@"manifestWeasisSeriesStudyInstanceUID"],studyInstance[5]]
                                                     dataUsingEncoding:NSUTF8StringEncoding],
                                                    seriesData
                                                    );
                             NSMutableArray *seriesArray=[NSJSONSerialization JSONObjectWithData:seriesData options:0 error:nil];
                             for (NSArray *seriesInstance in seriesArray)
                             {
                                 [weasisManifest appendFormat:
                                  @"<Series SeriesInstanceUID=\"%@\" SeriesDescription=\"%@\" SeriesNumber=\"%@\" Modality=\"%@\"  WadorsURI=\"/studies/%@/series/%@\">\r",
                                  seriesInstance[0],
                                  seriesInstance[1],
                                  seriesInstance[2],
                                  seriesInstance[3],
                                  studyInstance[5],
                                  seriesInstance[0]
                                  ];
                                 
                                 //instances
                                 NSMutableData *instanceData=[NSMutableData data];
                                 int instanceResult=task(@"/bin/bash",
                                                       @[@"-s"],
                                                       [[NSString stringWithFormat:thisSql[@"manifestWeasisInstanceSeriesInstanceUID"],seriesInstance[0]]
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
                 return [GCDWebServerDataResponse responseWithData:[weasisManifest dataUsingEncoding:NSUTF8StringEncoding] contentType:@"application/json"];
         }
         ];
        



#pragma mark /bir/weasisManifest
//---------------------------------------------------------------------------
// http://{remotepcs}/bir/weasisManifest?accessionNumber=123&custodianUID=1.2
//----------------------------------------------------------------------------

        [httpdicomServer addHandlerForMethod:@"GET"
                                       path:@"/bir/weasisManifest"
                               requestClass:[GCDWebServerRequest class]
                               processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             //request parts logging
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             NSString *q=requestURL.query;
             GWS_LOG_INFO(@"%@%@?%@",b,p,q);

 
             //request validation
             NSString *accessionNumber=[request.query objectForKey:@"accessionNumber"];
             NSString *pcs=[request.query objectForKey:@"pcs"];
             if (   ([request.query count]==2)
                 && accessionNumber
                 && ([accessionNumber length]<17)
                 && [SHRegex numberOfMatchesInString:accessionNumber options:0 range:NSMakeRange(0,[accessionNumber length])]
                 && pcs
                 && ([pcs length]<65)
                 && [UIRegex numberOfMatchesInString:pcs options:0 range:NSMakeRange(0,[pcs length])]
                 && [devs objectForKey:pcs]
                )
             {
                 NSString *accessionNumberURL=[accessionNumber stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                 //pacs params
                 NSDictionary *pacsDict=devs[@"pcs"];
                 
#pragma mark allow other select (sql, dicom Q/R)
                 
                 NSString *qidoRS=pacsDict[@"qidoRS"];
                 NSString *aet=pacsDict[@"aet"];
                 
                 //weasisManifest
                 NSMutableString *weasisManifest=[NSMutableString stringWithCapacity:10000];
                 [weasisManifest appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r"];
                 [weasisManifest appendString:@"<wado_query wadoURL=\"%@\" requireOnlySOPInstanceUID=\"false\" additionnalParameters=\"%@\">\r"];

                 //study list
                 NSString *studyURL=nil;
                 if ([[pacsDict objectForKey:@"accessionNumberIssuer"]boolValue]==true)
                     studyURL=[NSString stringWithFormat:@"%@/%@/studies?AccessionNumber=%@&00080051.00400032=%@&00080051.00400033=ISO",qidoRS,aet,accessionNumberURL,pcs];
                 else studyURL=[NSString stringWithFormat:@"%@/%@/studies?AccessionNumber=%@",qidoRS,aet,accessionNumberURL];
                 GWS_LOG_INFO(@"-> %@",studyURL);
                 NSData *studyJson=[NSData dataWithContentsOfURL:[NSURL URLWithString:studyURL]];
                 NSArray *studyArray=[NSJSONSerialization JSONObjectWithData:studyJson options:0 error:nil];
                 NSUInteger studyArrayCount=[studyArray count];
                 //GWS_LOG_INFO(@"%@",[studyArray description]);

                 //the accessionNumber may join more than one study of one or more patient !!!
                 //look for patient roots first
                 NSMutableArray *p=[NSMutableArray array];
                 for (NSDictionary *studyInstance in studyArray)
                 {
                     NSString *ii=[[studyInstance objectForKey:@"00100021"]objectForKey:@"Value"];
                     if (!ii) ii=@"";
                     [p addObject:[[[[studyInstance objectForKey:@"00100020"]objectForKey:@"Value"]objectAtIndex:0]stringByAppendingPathComponent:ii]];
                 }
             
                 //each patient
                 NSMutableDictionary *patientStudy=[NSMutableDictionary dictionaryWithCapacity:32];
                 for (NSString *patient in [NSSet setWithArray:p])
                 {
                     NSUInteger studyIndex=[p indexOfObject:patient];
                     [patientStudy setDictionary:[studyArray objectAtIndex:studyIndex]];
                     
                     NSString *PatientName=[[[[patientStudy objectForKey:@"00100010"]objectForKey:@"Value"]objectAtIndex:0]valueForKey:@"Alphabetic"];
                     if (!PatientName) PatientName=@"";
                     NSString *PatientID=[[[patientStudy objectForKey:@"00100020"]objectForKey:@"Value"]objectAtIndex:0];
                     if (!PatientID) PatientID=@"";
                     NSString *IssuerOfPatientID=[[[patientStudy objectForKey:@"00100021"]objectForKey:@"Value"]objectAtIndex:0];
                     if (!IssuerOfPatientID) IssuerOfPatientID=@"";
                     NSString *PatientBirthDate=[[[patientStudy objectForKey:@"00100030"]objectForKey:@"Value"]objectAtIndex:0];
                     if (!PatientBirthDate) PatientBirthDate=@"";
                     NSString *PatientSex=[[[patientStudy objectForKey:@"00100040"]objectForKey:@"Value"]objectAtIndex:0];
                     if (!PatientSex) PatientSex=@"";
                     
                     [weasisManifest appendFormat:@"<Patient PatientName=\"%@\" PatientID=\"%@\" IssuerOfPatientID=\"%@\" PatientBirthDate=\"%@\" PatientSex=\"%@\">\r",PatientName,PatientID,IssuerOfPatientID,PatientBirthDate,PatientSex];
                     
                     //each study of this patient
                     while ([patientStudy count]>0)
                     {
                         NSString *SpecificCharacterSet=[[[patientStudy objectForKey:@"00080005"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!SpecificCharacterSet) SpecificCharacterSet=@"";
                         NSString *StudyInstanceUID=[[[patientStudy objectForKey:@"0020000D"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!StudyInstanceUID) StudyInstanceUID=@"";
                         NSString *AccessionNumber=[[[patientStudy objectForKey:@"00080050"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!AccessionNumber) AccessionNumber=@"";
                         NSString *RetrieveAETitle=[[[patientStudy objectForKey:@"00080054"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!RetrieveAETitle) RetrieveAETitle=@"";
                         NSString *StudyID=[[[patientStudy objectForKey:@"00200010"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!StudyID) StudyID=@"";
                         NSString *StudyDescription=[[[patientStudy objectForKey:@"00081030"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!StudyDescription) StudyDescription=@"";
                         NSString *StudyDate=[[[patientStudy objectForKey:@"00080020"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!StudyDate) StudyDate=@"";
                         NSString *StudyTime=[[[patientStudy objectForKey:@"00080030"]objectForKey:@"Value"]objectAtIndex:0];
                         if (!StudyTime) StudyTime=@"";
                         
                         [weasisManifest appendFormat:@"<Study SpecificCharacterSet=\"%@\" StudyInstanceUID=\"%@\" AccessionNumber=\"%@\" RetrieveAETitle=\"%@\" StudyID=\"%@\" StudyDescription=\"%@\" StudyDate=\"%@\" StudyTime=\"%@\">\r",SpecificCharacterSet, StudyInstanceUID,AccessionNumber,RetrieveAETitle,StudyID,StudyDescription,StudyDate,StudyTime];
                         
                         //patient study series list
                         NSString *seriesURL=[NSString stringWithFormat:@"%@/%@/studies/%@/series",qidoRS,aet,StudyInstanceUID];
                         GWS_LOG_INFO(@"-> %@",seriesURL);
                         NSData *seriesJson=[NSData dataWithContentsOfURL:[NSURL URLWithString:seriesURL]];
                         NSArray *seriesArray=[NSJSONSerialization JSONObjectWithData:seriesJson options:0 error:nil];

                         for (NSDictionary *series in seriesArray)
                         {
                             NSString *SeriesInstanceUID=[[[series objectForKey:@"0020000E"]objectForKey:@"Value"]objectAtIndex:0];
                             if (!SeriesInstanceUID) SeriesInstanceUID=@"";
                             NSString *SeriesDescription=[[[series objectForKey:@"0008103E"]objectForKey:@"Value"]objectAtIndex:0];
                             if (!SeriesDescription) SeriesDescription=@"";
                             NSString *SeriesNumber=[[[series objectForKey:@"00200011"]objectForKey:@"Value"]objectAtIndex:0];
                             if (!SeriesNumber) SeriesNumber=@"";
                             NSString *Modality=[[[series objectForKey:@"00080060"]objectForKey:@"Value"]objectAtIndex:0];
                             if (!Modality) Modality=@"";
                             
                             [weasisManifest appendFormat:@"<Series SeriesInstanceUID=\"%@\" SeriesDescription=\"%@\" SeriesNumber=\"%@\" Modality=\"%@\">\r",SeriesInstanceUID,SeriesDescription,SeriesNumber,Modality];
                             
                             //patient study series instances list
                             NSString *instanceURL=[NSString stringWithFormat:@"%@/%@/studies/%@/series/%@/instances",qidoRS,aet,StudyInstanceUID,SeriesInstanceUID];
                             GWS_LOG_INFO(@"-> %@",instanceURL);
                             NSData *instanceJson=[NSData dataWithContentsOfURL:[NSURL URLWithString:instanceURL]];
                             NSArray *instanceArray=[NSJSONSerialization JSONObjectWithData:instanceJson options:0 error:nil];
                             
                             for (NSDictionary *instance in instanceArray)
                             {
                                 NSString *SOPInstanceUID=[[[instance objectForKey:@"00080018"]objectForKey:@"Value"]objectAtIndex:0];
                                 if (!SeriesInstanceUID) SeriesInstanceUID=@"";
                                 NSString *InstanceNumber=[[[instance objectForKey:@"00200013"]objectForKey:@"Value"]objectAtIndex:0];
                                 if (!InstanceNumber) InstanceNumber=@"";
                                 NSString *SOPClassUID=[[[instance objectForKey:@"00080016"]objectForKey:@"Value"]objectAtIndex:0];
                                 if (!SOPClassUID) SOPClassUID=@"";
                                 
                                 [weasisManifest appendFormat:@"<Instance SOPInstanceUID=\"%@\" InstanceNumber=\"%@\" SOPClassUID=\"%@\"/>\r",SOPInstanceUID,InstanceNumber,SOPClassUID];
                             }
                             
                             [weasisManifest appendString:@"</Series>\r"];
                         }
                         
                         [weasisManifest appendString:@"</Study>\r"];
                         
                         //next study of this patient
                         if (studyIndex<studyArrayCount)
                         {
                             studyIndex++;
                             studyIndex=[p indexOfObject:patient inRange:NSMakeRange(studyIndex,studyArrayCount-studyIndex)];
                             if (studyIndex==NSNotFound)[patientStudy removeAllObjects];
                             else [patientStudy setDictionary:[studyArray objectAtIndex:studyIndex]];
                         }
                         else [patientStudy removeAllObjects];
                     }
                     [weasisManifest appendString:@"</Patient>\r"];
                 }
                 
                 [weasisManifest appendString:@"</wado_query>\r"];
                 //GWS_LOG_INFO(@"%@",weasisManifest);
                 
                 return [GCDWebServerDataResponse responseWithData:[weasisManifest dataUsingEncoding:NSUTF8StringEncoding] contentType:@"application/xml"];
             }
             GWS_LOG_WARNING(@"incorrect syntax for request /weasisManifest");
             return [GCDWebServerDataResponse responseWithText:@"incorrect syntax for request /weasisManifest"];
         }
         ];
#pragma mark -
#pragma mark _____________redirects dev0, dicom (local, (pcs) remoto_____________

#pragma mark /pcs
        
        NSRegularExpression *pcsregex = [NSRegularExpression regularExpressionWithPattern:@"^/pcs/[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*(/.*)?$" options:NSRegularExpressionCaseInsensitive error:NULL];

        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:pcsregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             //request parts logging
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             NSString *q=requestURL.query;
             NSMutableArray *pComponent=[NSMutableArray arrayWithArray:[p componentsSeparatedByString:@"/"]];
             NSString *oid=[NSString stringWithString:pComponent[2]];
             NSString *oidURLString=[[devs objectForKey:oid]objectForKey:@"pcsurl"];
             if (oidURLString){
                 [pComponent removeObjectAtIndex:2];
                 [pComponent removeObjectAtIndex:1];
                 NSString *redirectString;
                 if (q){
                     redirectString=[NSString stringWithFormat:@"%@%@?%@&ian=%@",oidURLString,[pComponent componentsJoinedByString:@"/"],q,oid];
                 }
                 else {
                     redirectString=[NSString stringWithFormat:@"%@%@?ian=%@",oidURLString,[pComponent componentsJoinedByString:@"/"],oid];
                 }
                 GWS_LOG_INFO(@"%@%@?%@ -> %@",b,p,q,redirectString);
                 
                 //tenemos una orden a realizar por PCS remoto
                 //si es un query, conviene obtener la respuesta, y luego devolverla al cliente, cambiando el wado para que vaya a lo local
                 //si es un fetch wado o wado rest, cargar los archivos en dev0
                 
                 
                 return [GCDWebServerResponse
                         responseWithRedirect:[NSURL URLWithString:redirectString]
                         permanent:YES
                         ];
             }
             else {
                 GWS_LOG_INFO(@"%@%@?%@ doesn´t match any known OID",b,p,q);
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:
                         @"%@%@?%@ doesn´t match any known OID",b,p,q];
             }
         }
         ];
        
#pragma mark /pcs/dev[]
        
        NSMutableString *devregexString=[NSMutableString string];
        for (NSUInteger i=1;i<devCount-1;i++)
        {
            [devregexString appendFormat:@"^/pcs/%@|",devOids[i]];
        }
        [devregexString appendFormat:@"^/pcs/%@",devOids[devCount-1]];
        NSRegularExpression *devregex=[NSRegularExpression regularExpressionWithPattern:devregexString options:NSRegularExpressionCaseInsensitive error:NULL];


        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:devregex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
/*             //qido,wado,stow?
             //protocolo?
             if ([request.method isEqualToString:@"POST"])
             {
                 //probable stow
             }
             else if ([pComponents count]==4)
             {
                 //probable //qido studies, series or instances
             }
             else if ([pComponents count]==3)
             {
                 //probable wado-uri
             }
*/
             
             
             //request parts logging
             NSURL *requestURL=request.URL;
             NSString *bSlash=requestURL.baseURL.absoluteString;
             NSString *b=[bSlash substringToIndex:[bSlash length]-1];
             NSString *p=requestURL.path;
             NSString *q=requestURL.query;
             NSMutableArray *pComponents=(NSMutableArray*)[p componentsSeparatedByString:@"/"];
             NSString *oid=[NSString stringWithString:pComponents[2]];
             [pComponents removeObjectsInRange:NSMakeRange(1,2)];
             NSString *redirectString;
             if (q){redirectString=[NSString stringWithFormat:@"%@?%@&pcs=%@",[pComponents componentsJoinedByString:@"/"],q,oid];}
             else {redirectString=[NSString stringWithFormat:@"%@?pcs=%@",[pComponents componentsJoinedByString:@"/"],oid];}
             GWS_LOG_INFO(@"dev1: %@%@?%@ -> %@",b,p,q,redirectString);
             
             //redirect dentro del PCS local
             return [GCDWebServerResponse
                     responseWithRedirect:[NSURL URLWithString:redirectString]
                     permanent:NO
                     ];
         }
         ];

#pragma mark /pcs/dev[0]
        
        NSRegularExpression *dev0regex=[NSRegularExpression regularExpressionWithPattern:[@"^/pcs/" stringByAppendingString:devOids[0]] options:NSRegularExpressionCaseInsensitive error:NULL];

        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:dev0regex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSString *p=[request.URL.path substringFromIndex:5+[devOids[0] length]];
             NSString *q=request.URL.query;
             NSString *redirectString;
             if (q && [q length])
             {
                 if (p && [p length]) redirectString=[NSString stringWithFormat:@"%@?%@",p,q];
                 else redirectString=[NSString stringWithFormat:@"/?%@",q];
             }
             else
             {
                 if (p && [p length]) redirectString=p;
                 else redirectString=@"/";
             }

             GWS_LOG_INFO(@"/pcs/dev[0] -> %@",redirectString);
             
             return [GCDWebServerResponse
                     responseWithRedirect:[NSURL URLWithString:redirectString]
                     permanent:NO];
          }
         ];

#pragma mark -
#pragma mark orgs y aets

        NSRegularExpression *orgtsRegex = [NSRegularExpression regularExpressionWithPattern:@"^/orgts.*$" options:0 error:NULL];

        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:orgtsRegex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSURL *requestURL=request.URL;
             NSString *p=requestURL.path;
             NSMutableArray *pComponents=(NSMutableArray*)[p componentsSeparatedByString:@"/"];
             NSUInteger pCount=[pComponents count];
             if (![pComponents[1] isEqualToString:@"orgts"])
             {
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"service '%@' not found",pComponents[1]];
             }
             if (pCount==2)
             {
//orgts
                 return [GCDWebServerDataResponse responseWithData:orgtsData contentType:@"application/json"];
             }
             
             NSUInteger lOrg = [pComponents[2]length];
             if (  (lOrg>16)
                 ||![SHRegex numberOfMatchesInString:pComponents[2] options:0 range:NSMakeRange(0,lOrg)]
                 )
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"org titles should conform to DICOM SH datatype. '%@' doesn´t.",pComponents[2]];

             NSUInteger orgtIndex=[orgtsArray indexOfObject:pComponents[2]];
             if (orgtIndex==NSNotFound)
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"org '%@' not found",pComponents[2]];

             if (pCount==3)
             {
                 NSData *orgiData = [NSJSONSerialization dataWithJSONObject:[NSArray arrayWithObject:[orgisArray objectAtIndex:orgtIndex]] options:0 error:nil];
                 return [GCDWebServerDataResponse responseWithData:orgiData contentType:@"application/json"];
             }
//pCount>3
             if (![pComponents[3]isEqualToString:@"aets"])
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"third component of the path '%@' should be 'aets'",p];

//orgts/{title}/aets
             if (pCount==4)
                 return [GCDWebServerDataResponse responseWithData:[NSJSONSerialization dataWithJSONObject:[orgtsaets objectForKey:pComponents[2]] options:0 error:nil] contentType:@"application/json"];
//pCount>4
             NSUInteger lAet = [pComponents[4]length];
             if (  (lAet>16)
                 ||![SHRegex numberOfMatchesInString:pComponents[4] options:0 range:NSMakeRange(0,lAet)]
                 )
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"ae titles should conform to DICOM SH datatype. '%@' doesn´t.",pComponents[4]];

             if (pCount==5)
             {
//orgts/{title}/aets/{title}
                 NSUInteger aetIndex=[[orgtsaets objectForKey:pComponents[2]] indexOfObject:pComponents[4]];
                 if (aetIndex==NSNotFound)
                     return [GCDWebServerErrorResponse responseWithClientError:404 message:@"aet '%@' not found",pComponents[4]];
                 return [GCDWebServerDataResponse responseWithData:
                             [NSJSONSerialization dataWithJSONObject:
                              [NSArray arrayWithObject:
                               [
                                [orgisaeis objectForKey:
                                 [orgisArray objectAtIndex:orgtIndex]
                                 ]
                                objectAtIndex:aetIndex
                                ]
                               ] options:0 error:nil
                              ]
                              contentType:@"application/json"
                             ];
             }
             return [GCDWebServerErrorResponse responseWithClientError:404 message:@"too many segments in path '%@'",p];
         }
         ];
        
        
        NSRegularExpression *orgisRegex = [NSRegularExpression regularExpressionWithPattern:@"^/orgis.*$" options:0 error:NULL];
        
        [httpdicomServer addHandlerForMethod:@"GET"
                       pathRegularExpression:orgisRegex
                                requestClass:[GCDWebServerRequest class]
                                processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request)
         {
             NSURL *requestURL=request.URL;
             NSString *p=requestURL.path;
             NSMutableArray *pComponents=(NSMutableArray*)[p componentsSeparatedByString:@"/"];
             NSUInteger pCount=[pComponents count];
             if (![pComponents[1] isEqualToString:@"orgis"])
             {
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"service '%@' not found",pComponents[1]];
             }
             if (pCount==2)
             {
//orgis
                 return [GCDWebServerDataResponse responseWithData:orgisData contentType:@"application/json"];
             }
             
             NSUInteger lOrg = [pComponents[2]length];
             if (  (lOrg>64)
                 ||![UIRegex numberOfMatchesInString:pComponents[2] options:0 range:NSMakeRange(0,lOrg)]
                 )
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"org titles should conform to DICOM UI datatype. '%@' doesn´t.",pComponents[2]];
             
             NSUInteger orgiIndex=[orgisArray indexOfObject:pComponents[2]];
             if (orgiIndex==NSNotFound)
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"org '%@' not found",pComponents[2]];
             
             if (pCount==3)
             {
//orgis/{oid}
                 NSData *orgtData = [NSJSONSerialization dataWithJSONObject:[NSArray arrayWithObject:[orgtsArray objectAtIndex:orgiIndex]] options:0 error:nil];
                 return [GCDWebServerDataResponse responseWithData:orgtData contentType:@"application/json"];
             }
//pCount>3
             if (![pComponents[3]isEqualToString:@"aeis"])
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"third component of the path '%@' should be 'aeis'",p];
             
//orgis/{oid}/aeis
             if (pCount==4)
                 return [GCDWebServerDataResponse responseWithData:[NSJSONSerialization dataWithJSONObject:[orgisaeis objectForKey:pComponents[2]] options:0 error:nil] contentType:@"application/json"];
//pCount>4
             NSUInteger lAet = [pComponents[4]length];
             if (  (lAet>64)
                 ||![UIRegex numberOfMatchesInString:pComponents[4] options:0 range:NSMakeRange(0,lAet)]
                 )
                 return [GCDWebServerErrorResponse responseWithClientError:404 message:@"ae titles should conform to DICOM UI datatype. '%@' doesn´t.",pComponents[4]];
             
             if (pCount==5)
             {
                 NSUInteger aeiIndex=[[orgisaeis objectForKey:pComponents[2]] indexOfObject:pComponents[4]];
                 if (aeiIndex==NSNotFound)
                     return [GCDWebServerErrorResponse responseWithClientError:404 message:@"aei '%@' not found",pComponents[4]];
//orgis/{oid}/aeis/{oid}
                 return [GCDWebServerDataResponse responseWithData:
                         [NSJSONSerialization dataWithJSONObject:
                          [NSArray arrayWithObject:
                           [
                            [orgtsaets objectForKey:
                             [orgtsArray objectAtIndex:orgiIndex]
                             ]
                            objectAtIndex:aeiIndex
                            ]
                           ] options:0 error:nil
                          ]
                          contentType:@"application/json"
                         ];
             }
             return [GCDWebServerErrorResponse responseWithClientError:404 message:@"too many segments in path '%@'",p];
         }
         ];

#pragma mark run
        [httpdicomServer runWithPort:pcsPort bonjourName:nil];
        
        // runloop
        _run = YES;
        void* handler = signal(SIGINT, _SignalHandler);
        if (handler != SIG_ERR) {
            while (_run) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
            }
            
            if (httpdicomServer) {
                [httpdicomServer stop];
            }
            
            signal(SIGINT, handler);
        }
        
    }//end autorelease pool
    return success ? 0 : -1;
}
