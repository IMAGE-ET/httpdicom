//
//  NSURLComponents+PCS.m
//  httpdicom
//
//  Created by jacquesfauquex on 20171122.
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


#import "NSURLComponents+PCS.h"

static NSRegularExpression *UIRegex;
static NSRegularExpression *SHRegex;

@implementation NSURLComponents (PCS)

//generic
+ (void)initializeStaticRegex
{
    UIRegex = [NSRegularExpression regularExpressionWithPattern:@"^[1-2](\\d)*(\\.0|\\.[1-9](\\d)*)*$" options:0 error:NULL];
    SHRegex = [NSRegularExpression regularExpressionWithPattern:@"^(?:\\s*)([^\\r\\n\\f\\t]*[^\\r\\n\\f\\t\\s])(?:\\s*)$" options:0 error:NULL];
}

-(NSInteger)nextQueryItemsIndexForPredicateString:(NSString*)predicateString key:(NSString*)key value:(NSString*)value startIndex:(NSInteger)startIndex
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateString,key,value];
    if (startIndex < 0) return NSNotFound;
    while (startIndex < [self.queryItems count]) {
        if ([predicate evaluateWithObject:self.queryItems[startIndex]]) return startIndex;
        startIndex++;
    }
    return NSNotFound;
}

-(NSString*)firstQueryItemNamed:(NSString*)name
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K=%@",@"name",name];
    for (NSURLQueryItem *item in self.queryItems)
    {
        if ([predicate evaluateWithObject:item]) return item.value;
    }
    return nil;
}

-(NSString*)queryWithoutItemNamed:(NSString*)name
{
    NSMutableString *q=[NSMutableString string];
    NSUInteger c=[self.queryItems count];
    if (c==0)return @"";
    for (int i=0; i<[self.queryItems count];i++)
    {
        if (![self.queryItems[i].name isEqualToString:name])[q appendFormat:@"%@=%@&",self.queryItems[i].name,self.queryItems[i].value];
    }
    [q deleteCharactersInRange:NSMakeRange([q length]-1,1)];
    return [NSString stringWithString:q];
}

//wado
-(NSString*)wadoDicomQueryItemsError
{
    //?requestType=WADO
    //&contentType=application/dicom
    //&studyUID={studyUID}
    //&seriesUID={seriesUID}
    //&objectUID={objectUID}

    //uses first occurrence only
    
    BOOL requestType=false;
    BOOL contentType=false;
    BOOL studyUID=false;
    BOOL seriesUID=false;
    BOOL objectUID=false;
    
    for (NSURLQueryItem* i in self.queryItems)
    {
        if (!requestType && [i.name isEqualToString:@"requestType"] && [i.value isEqualToString:@"WADO"]) requestType=true;
        else if (!contentType && [i.name isEqualToString:@"contentType"] && [i.value isEqualToString:@"application/dicom"]) contentType=true;
        else if (!studyUID && [i.name isEqualToString:@"studyUID"] && [UIRegex numberOfMatchesInString:i.value options:0 range:NSMakeRange(0,[i.value length])]) studyUID=true;
        else if (!seriesUID && [i.name isEqualToString:@"seriesUID"] && [UIRegex numberOfMatchesInString:i.value options:0 range:NSMakeRange(0,[i.value length])]) seriesUID=true;
        else if (!objectUID && [i.name isEqualToString:@"objectUID"] && [UIRegex numberOfMatchesInString:i.value options:0 range:NSMakeRange(0,[i.value length])]) objectUID=true;
    }
    if (requestType && contentType && studyUID && seriesUID && objectUID) return nil;
    if (contentType==false) return @"contentType";
    if (studyUID==false) return @"studyUID";
    if (seriesUID==false) return @"seriesUID";
    if (objectUID==false) return @"objectUID";
    return @"error";
}

@end
