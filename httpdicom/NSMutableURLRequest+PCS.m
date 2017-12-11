//
//  NSMutableURLRequest+PCS.m
//  httpdicom
//
//  Created by jacquesfauquex on 2017129.
//  Copyright © 2017 ridi.salud.uy. All rights reserved.
//

#import "NSMutableURLRequest+PCS.h"

@implementation NSMutableURLRequest (PCS)

+(id)PUTpatient:(NSString*)URLString name:(NSString*)name pid:(NSString*)pid issuer:(NSString*)issuer birthdate:(NSString*)birthdate sex:(NSString*)sex contentType:(NSString*)contentType timeout:(NSTimeInterval)timeout
{
    if (!URLString || ![URLString length]) return nil;
    if (!pid || ![pid length]) return nil;
    if (!issuer || ![issuer length]) return nil;
    if ([contentType isEqualToString:@"application/json"])
    {
        id request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URLString]
                                             cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                         timeoutInterval:timeout
                      ];
        NSLog(@"%@",[request URL]);

        // https://developer.apple.com/reference/foundation/nsurlrequestcachepolicy?language=objc;
        //NSURLRequestReloadIgnoringCacheData

        [request setHTTPMethod:@"PUT"];
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];

        NSMutableString *json=[NSMutableString string];
        [json appendString:@"{\"00080005\": {\"vr\":\"CS\",\"Value\":[\"ISO_IR 192\"]},"];//utf8
        [json appendFormat:@"\"00100010\":{\"vr\":\"PN\",\"Value\":[\"%@\"]},",name];
        [json appendFormat:@"\"00100020\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",pid];
        [json appendFormat:@"\"00100021\":{\"vr\":\"LO\",\"Value\":[\"%@\"]},",issuer];
        [json appendFormat:@"\"00100030\":{\"vr\":\"DA\",\"Value\":[\"%@\"]},",birthdate];
        [json appendFormat:@"\"00100040\":{\"vr\":\"CS\",\"Value\":[\"%@\"]}}",sex];
        [request setHTTPBody:[json dataUsingEncoding:NSUTF8StringEncoding]];

        return request;
    }
    return nil;
}

+(id)POSTmwlitem:(NSString*)URLString CS:(NSString*)CS aet:(NSString*)aet DA:(NSString*)DA TM:(NSString*)TM modality:(NSString*)modality accessionNumber:(NSString*)accessionNumber status:(NSString*)status procCode:(NSString*)procCode procScheme:(NSString*)procScheme procMeaning:(NSString*)procMeaning priority:(NSString*)priority name:(NSString*)name pid:(NSString*)pid issuer:(NSString*)issuer birthdate:(NSString*)birthdate sex:(NSString*)sex contentType:(NSString*)contentType timeout:(NSTimeInterval)timeout
{
    if (!URLString || ![URLString length]) return nil;
    if (!pid || ![pid length]) return nil;
    if (!issuer || ![issuer length]) return nil;
    if ([contentType isEqualToString:@"application/json"])
    {
        id request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URLString]
                                             cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                         timeoutInterval:timeout
                      ];
        // https://developer.apple.com/reference/foundation/nsurlrequestcachepolicy?language=objc;
        //NSURLRequestReloadIgnoringCacheData
        
        [request setHTTPMethod:@"POST"];
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
        
        //crear json for workitem http://dicom.nema.org/medical/Dicom/2015a/output/chtml/part03/sect_C.4.10.html
        //doesn´t indicate optional, nor mandatory metadata...
        
        //minimal format, one step with accessionNumber=procid=stepid=studyiuid
        NSMutableString *json=[NSMutableString string];
        [json appendFormat:@"{\"00080005\": {\"vr\":\"CS\",\"Value\":[\"%@\"]},",CS];
        [json appendString:@"\"00400100\": {\"vr\":\"SQ\",\"Value\":[{"];
        if (aet) [json appendFormat:@"\"00400001\":{\"vr\":\"AE\",\"Value\":[\"%@\"]},",aet];
        [json appendFormat:@"\"00400002\":{\"vr\":\"DA\",\"Value\":[\"%@\"]},",DA];
        [json appendFormat:@"\"00400003\":{\"vr\":\"TM\",\"Value\":[\"%@\"]},",TM];
        [json appendFormat:@"\"00080060\":{\"vr\":\"CS\",\"Value\":[\"%@\"]},",modality];
        [json appendFormat:@"\"00400009\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",accessionNumber];//<STEPID> (=Accession Number)
        [json appendFormat:@"\"00400020\":{\"vr\":\"CS\",\"Value\":[\"%@\"]}}]},",status];
        [json appendFormat:@"\"00401001\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",accessionNumber];//<PROCID> (=Accession Number)
        [json appendString:@"\"00321064\":{\"vr\":\"SQ\",\"Value\":[{"];
        [json appendFormat:@"\"00080100\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",procCode];
        [json appendFormat:@"\"00080102\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",procScheme];
        [json appendFormat:@"\"00080104\":{\"vr\":\"LO\",\"Value\":[\"%@\"]}}]},",procMeaning];
        [json appendFormat:@"\"0020000D\":{\"vr\":\"UI\",\"Value\":[\"%@\"]},",accessionNumber];//<STUDYUID>
        [json appendFormat:@"\"00401003\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",priority];
        [json appendFormat:@"\"00080050\":{\"vr\":\"SH\",\"Value\":[\"%@\"]},",accessionNumber];
        [json appendFormat:@"\"00100010\":{\"vr\":\"PN\",\"Value\":[\"%@\"]},",name];
        [json appendFormat:@"\"00100020\":{\"vr\":\"LO\",\"Value\":[\"%@\"]},",pid];
        [json appendFormat:@"\"00100021\":{\"vr\":\"LO\",\"Value\":[\"%@\"]},",issuer];
        [json appendFormat:@"\"00100030\":{\"vr\":\"DA\",\"Value\":[\"%@\"]},",birthdate];
        [json appendFormat:@"\"00100040\":{\"vr\":\"CS\",\"Value\":[\"%@\"]}}",sex];

        [request setHTTPBody:[json dataUsingEncoding:NSUTF8StringEncoding]];
        
        return request;
    }
    return nil;
}

@end
