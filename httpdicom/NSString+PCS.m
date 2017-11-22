//
//  NSString+PCS.m
//  httpdicom
//
//  Created by jacquesfauquex on 2016-10-11.
//  Copyright © 2018 opendicom.com. All rights reserved.
//

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


#import "NSString+PCS.h"
#import <netdb.h>
#import <CommonCrypto/CommonDigest.h>

@implementation NSString (PCS)

+(NSString*)regexDicomString:(NSString*)dicomString withFormat:(NSString*)formatString
{
    NSString *regex;
    regex = [dicomString stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    regex = [regex stringByReplacingOccurrencesOfString:@"{" withString:@"\\{"];
    regex = [regex stringByReplacingOccurrencesOfString:@"}" withString:@"\\}"];
    regex = [regex stringByReplacingOccurrencesOfString:@"?" withString:@"\\?"];
    regex = [regex stringByReplacingOccurrencesOfString:@"+" withString:@"\\+"];
    regex = [regex stringByReplacingOccurrencesOfString:@"[" withString:@"\\["];
    regex = [regex stringByReplacingOccurrencesOfString:@"(" withString:@"\\("];
    regex = [regex stringByReplacingOccurrencesOfString:@")" withString:@"\\)"];
    regex = [regex stringByReplacingOccurrencesOfString:@"^" withString:@"\\^"];
    regex = [regex stringByReplacingOccurrencesOfString:@"$" withString:@"\\$"];
    regex = [regex stringByReplacingOccurrencesOfString:@"|" withString:@"\\|"];
    regex = [regex stringByReplacingOccurrencesOfString:@"/" withString:@"\\/"];
    regex = [regex stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
    regex = [regex stringByReplacingOccurrencesOfString:@"*" withString:@".*"];
    regex = [regex stringByReplacingOccurrencesOfString:@"_" withString:@"."];
    return [NSString stringWithFormat:formatString,regex];
}


+(NSString*)mysqlEscapedFormat:(NSString*)format fieldString:(NSString*)field valueString:(NSString*)value;
{
    NSString *escapedValue;
    escapedValue = [value stringByReplacingOccurrencesOfString:@"?" withString:@"_"];
    escapedValue = [escapedValue stringByReplacingOccurrencesOfString:@"*" withString:@"%"];
    return [NSString stringWithFormat:format,field,escapedValue];
}

+(NSString*)stringFromSockAddr:(const struct sockaddr*)addr includeService:(BOOL)includeService
{
    NSString* string = nil;
    char hostBuffer[NI_MAXHOST];
    char serviceBuffer[NI_MAXSERV];
    if (getnameinfo(addr, addr->sa_len, hostBuffer, sizeof(hostBuffer), serviceBuffer, sizeof(serviceBuffer), NI_NUMERICHOST | NI_NUMERICSERV | NI_NOFQDN) >= 0) {
        string = includeService ? [NSString stringWithFormat:@"%s:%s", hostBuffer, serviceBuffer] : [NSString stringWithUTF8String:hostBuffer];
    }
    return string;
}

-(NSString*)MD5String
{
    const char *cStr = [self UTF8String];
    unsigned char digest[16];
    CC_MD5( cStr, (unsigned int)strlen(cStr), digest );
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    return  output;
}

-(NSString*)normalizeHeaderValue
{

    NSRange range = [self rangeOfString:@";"];
    // Assume part before ";" separator is case-insensitive
    if (range.location != NSNotFound)
    {
        return [[[self substringToIndex:range.location] lowercaseString] stringByAppendingString:[self substringFromIndex:range.location]];
    }
    return [self lowercaseString];
}


-(NSString*)extractHeaderValueParameter:(NSString*)name
{
    NSString* parameter = nil;
    NSScanner* scanner = [[NSScanner alloc] initWithString:self];
    [scanner setCaseSensitive:NO];
    // Assume parameter names are case-insensitive
    NSString* string = [NSString stringWithFormat:@"%@=", name];
    if ([scanner scanUpToString:string intoString:NULL])
    {
        [scanner scanString:string intoString:NULL];
        if ([scanner scanString:@"\"" intoString:NULL]) {
            [scanner scanUpToString:@"\"" intoString:&parameter];
        } else {
            [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&parameter];
        }
    }
    return parameter;
}

-(NSString*)dcmDaFromDate
{
    if ([self length]==8)return self;
    if ([self length]<10)
    {
        NSLog(@"strange DA: '%@'",self);
        return @"";
    }
    return [NSString stringWithFormat:@"%@%@%@",
            [self substringWithRange:NSMakeRange(0,4)],
            [self substringWithRange:NSMakeRange(5,2)],
            [self substringWithRange:NSMakeRange(8,2)]
            ];
}

-sqlFilterWithStart:(NSString*)start end:(NSString*)end
{
    NSUInteger startLength=[start length];
    NSUInteger endLength=[end length];
    if (!start || !end || startLength+endLength==0) return @"";

    NSString *isoStart=nil;
    switch (startLength) {
        case 0:;
            isoStart=@"";
            break;
        case 8:;
            isoStart=[NSString stringWithFormat:@"%@-%@-%@",
                  [start substringWithRange:NSMakeRange(0, 4)],
                  [start substringWithRange:NSMakeRange(4, 2)],
                  [start substringWithRange:NSMakeRange(6, 2)]
                  ];
        break;
        case 10:;
            isoStart=start;
        
        default:
            return @"";
        break;
    }

    NSString *isoEnd=nil;
    switch (endLength) {
        case 0:;
        isoEnd=@"";
        break;
        case 8:;
        isoEnd=[NSString stringWithFormat:@"%@-%@-%@",
                  [end substringWithRange:NSMakeRange(0, 4)],
                  [end substringWithRange:NSMakeRange(4, 2)],
                  [end substringWithRange:NSMakeRange(6, 2)]
                  ];
        break;
        case 10:;
        isoEnd=end;
        
        default:
        return @"";
        break;
    }

    if (startLength==0) return [NSString stringWithFormat:@" AND DATE(%@) <= '%@'", self, isoEnd];
    else if (endLength==0) return [NSString stringWithFormat:@" AND DATE(%@) >= '%@'", self, isoStart];
    else if ([isoStart isEqualToString:isoEnd]) return [NSString stringWithFormat:@" AND DATE(%@) = '%@'", self, isoStart];
    else return [NSString stringWithFormat:@" AND DATE(%@) >= '%@' AND DATE(%@) <= '%@'", self, isoStart, self, isoEnd];
    
    return @"";
}
    
@end


