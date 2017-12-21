//
//  NSData+PCS.m
//  httpdicom
//
//  Created by jacquesfauquex on 2016-10-12.
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


#import "NSData+PCS.h"
#import "ODLog.h"

@implementation NSData (PCS)

static NSData *formDataPartName=nil;
static NSData *doubleQuotes=nil;
static NSData *contentType=nil;
static NSData *semicolon=nil;
static NSData *rnrn=nil;
static NSData *rn=nil;


+(NSData*)jsonpCallback:(NSString*)callback withDictionary:(NSDictionary*)dictionary
{
    NSMutableData *jsonp=[NSMutableData data];
    [jsonp appendData:[callback dataUsingEncoding:NSUTF8StringEncoding]];
    [jsonp appendData:[@"(" dataUsingEncoding:NSUTF8StringEncoding]];
    [jsonp appendData:[NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil]];
    [jsonp appendData:[@");" dataUsingEncoding:NSUTF8StringEncoding]];
    return [NSData dataWithData:jsonp];
}

+(NSData*)jsonpCallback:(NSString*)callback forDraw:(NSString*)draw withErrorString:(NSString*)error
{
    //https://datatables.net/manual/server-side#Returned-data
    return [NSData jsonpCallback:callback withDictionary:@{@"draw":draw,@"recordsTotal":@0,@"recordsFiltered":@0,@"data":@[],@"error":error}];
}


+(void)initPCS
{
    formDataPartName=[@"Content-Disposition: form-data; name=\"" dataUsingEncoding:NSASCIIStringEncoding];
    doubleQuotes=[@"\"" dataUsingEncoding:NSASCIIStringEncoding];
    contentType=[@"Content-Type: " dataUsingEncoding:NSASCIIStringEncoding];
    semicolon=[@";" dataUsingEncoding:NSASCIIStringEncoding];
    rnrn=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    rn=[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
}

-(NSDictionary*)parseNamesValuesTypesInBodySeparatedBy:(NSData*)separator
{
    //return datatype is array,because a param name may be repeated
    
    NSMutableArray *names=[NSMutableArray array];
    NSMutableArray *values=[NSMutableArray array];
    NSMutableArray *types=[NSMutableArray array];
    //there is a separator at the beginning and at the end
    NSRange containerRange=NSMakeRange(0,self.length);
    NSRange separatorRange=[self rangeOfData:separator options:0 range:containerRange];
    NSUInteger componentStart=separatorRange.location + separatorRange.length + 2;//2...0D0A
    containerRange.location=componentStart;
    containerRange.length=self.length - componentStart;
    
    //skip 0->first separator
    separatorRange=[self rangeOfData:separator options:0 range:containerRange];
    
    while (separatorRange.location != NSNotFound)
    {
        NSMutableData *dataChunk=[NSMutableData dataWithData:[self subdataWithRange:NSMakeRange(componentStart,separatorRange.location - componentStart - 4)]];//4... 0D0A
        
        //add object to types
        NSString *type;
        NSRange contentTypeRange=[dataChunk rangeOfData:contentType options:0 range:NSMakeRange(0,[dataChunk length])];
        if (contentTypeRange.location==NSNotFound) type=@"";
        else
        {
            NSUInteger start=contentTypeRange.location+contentTypeRange.length;
            NSRange semicolonRange=[dataChunk rangeOfData:semicolon options:0 range:NSMakeRange(start,[dataChunk length]-start)];
            NSRange rnRange=[dataChunk rangeOfData:rn options:0 range:NSMakeRange(start,[dataChunk length]-start)];
            if (   semicolonRange.location==NSNotFound
                || (    rnRange.location!=NSNotFound
                    &&  rnRange.location < semicolonRange.location)
                ) type=[[NSString alloc]initWithData:[dataChunk subdataWithRange:NSMakeRange(start,rnRange.location-start)] encoding:NSUTF8StringEncoding];
            else type=[[NSString alloc]initWithData:[dataChunk subdataWithRange:NSMakeRange(start,semicolonRange.location-start)] encoding:NSUTF8StringEncoding];
        }
        [types addObject:type];
        
        //remove everything until name
        NSRange formDataPartNameRange=[dataChunk rangeOfData:formDataPartName options:0 range:NSMakeRange(0,[dataChunk length])];
        if (!formDataPartNameRange.length) break;
        [dataChunk replaceBytesInRange:NSMakeRange(0,formDataPartNameRange.location + formDataPartNameRange.length) withBytes:NULL length:0];
        
        //add object to names
        NSRange doubleQuotesRange=[dataChunk rangeOfData:doubleQuotes options:0 range:NSMakeRange(0,[dataChunk length])];
        [names addObject:[[NSString alloc]initWithData:[dataChunk subdataWithRange:NSMakeRange(0,doubleQuotesRange.location)] encoding:NSUTF8StringEncoding]];
        
        //remove everything until rnrn
        NSRange rnrnRange=[dataChunk rangeOfData:rnrn options:0 range:NSMakeRange(0,[dataChunk length])];
        [dataChunk replaceBytesInRange:NSMakeRange(0,rnrnRange.location + rnrnRange.length) withBytes:NULL length:0];

        //add object to values
        if (  ![type length]
            || [type hasPrefix:@"text"]
            || [type hasPrefix:@"application/json"]
            || [type hasPrefix:@"application/dicom+json"]
            || [type hasPrefix:@"application/xml"]
            || [type hasPrefix:@"application/xml+json"]
            )[values addObject:[[NSString alloc]initWithData:dataChunk encoding:NSUTF8StringEncoding]];
        else [values addObject:[dataChunk base64EncodedStringWithOptions:0]];
        
        componentStart=separatorRange.location + separatorRange.length + 2;//2...0D0A
        containerRange.location=componentStart;
        containerRange.length=self.length - componentStart;
        
        separatorRange=[self rangeOfData:separator options:0 range:containerRange];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSArray arrayWithArray:names],
            @"names",
            [NSArray arrayWithArray:values],
            @"values",
            [NSArray arrayWithArray:types],
            @"types",
            nil];
}
@end
