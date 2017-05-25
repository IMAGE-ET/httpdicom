//
//  NSString+PCS.m
//  httpdicom
//
//  Created by jacquesfauquex on 2016-10-11.
//  Copyright © 2016 "opendicom" Jesros S.A. All rights reserved.
//

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

@end


