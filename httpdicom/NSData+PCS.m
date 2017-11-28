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

//***********************************************************************************************************
//  Function      : generateCRC32Table
//
//  Description   : Generates a lookup table for CRC calculations using a supplied polynomial.
//
//  Declaration   : void generateCRC32Table(uint32_t *pTable, uint32_t poly);
//
//  Parameters    : pTable
//                    A pointer to pre-allocated memory to store the lookup table.
//
//                  poly
//                    The polynomial to use in calculating the CRC table values.
//
//  Return Value  : None.
//***********************************************************************************************************
void generateCRC32Table(uint32_t *pTable, uint32_t poly)
{
    for (uint32_t i = 0; i <= 255; i++)
    {
        uint32_t crc = i;
        
        for (uint32_t j = 8; j > 0; j--)
        {
            if ((crc & 1) == 1)
                crc = (crc >> 1) ^ poly;
            else
                crc >>= 1;
        }
        pTable[i] = crc;
    }
}

//***********************************************************************************************************
//  Method        : crc32
//
//  Description   : Calculates the CRC32 of a data object using the default seed and polynomial.
//
//  Declaration   : -(uint32_t)crc32;
//
//  Parameters    : None.
//
//  Return Value  : The CRC32 value.
//***********************************************************************************************************
-(uint32_t)crc32
{
    return [self crc32WithSeed:DEFAULT_SEED usingPolynomial:DEFAULT_POLYNOMIAL];
}

//***********************************************************************************************************
//  Method        : crc32WithSeed:
//
//  Description   : Calculates the CRC32 of a data object using a supplied seed and default polynomial.
//
//  Declaration   : -(uint32_t)crc32WithSeed:(uint32_t)seed;
//
//  Parameters    : seed
//                    The initial CRC value.
//
//  Return Value  : The CRC32 value.
//***********************************************************************************************************
-(uint32_t)crc32WithSeed:(uint32_t)seed
{
    return [self crc32WithSeed:seed usingPolynomial:DEFAULT_POLYNOMIAL];
}

//***********************************************************************************************************
//  Method        : crc32UsingPolynomial:
//
//  Description   : Calculates the CRC32 of a data object using a supplied polynomial and default seed.
//
//  Declaration   : -(uint32_t)crc32UsingPolynomial:(uint32_t)poly;
//
//  Parameters    : poly
//                    The polynomial to use in calculating the CRC.
//
//  Return Value  : The CRC32 value.
//***********************************************************************************************************
-(uint32_t)crc32UsingPolynomial:(uint32_t)poly
{
    return [self crc32WithSeed:DEFAULT_SEED usingPolynomial:poly];
}

//***********************************************************************************************************
//  Method        : crc32WithSeed:usingPolynomial:
//
//  Description   : Calculates the CRC32 of a data object using supplied polynomial and seed values.
//
//  Declaration   : -(uint32_t)crc32WithSeed:(uint32_t)seed usingPolynomial:(uint32_t)poly;
//
//  Parameters    : seed
//                    The initial CRC value.
//
//                : poly
//                    The polynomial to use in calculating the CRC.
//
//  Return Value  : The CRC32 value.
//***********************************************************************************************************
-(uint32_t)crc32WithSeed:(uint32_t)seed usingPolynomial:(uint32_t)poly
{
    uint32_t *pTable = malloc(sizeof(uint32_t) * 256);
    generateCRC32Table(pTable, poly);
    
    uint32_t crc    = seed;
    uint8_t *pBytes = (uint8_t *)[self bytes];
    uint32_t length = (uint32_t)[self length];
    
    while (length--)
    {
        crc = (crc>>8) ^ pTable[(crc & 0xFF) ^ *pBytes++];
    }
    
    free(pTable);
    return crc ^ 0xFFFFFFFFL;
}

+(void)initPCS
{
    formDataPartName=[@"Content-Disposition: form-data; name=\"" dataUsingEncoding:NSASCIIStringEncoding];
    doubleQuotes=[@"\"" dataUsingEncoding:NSASCIIStringEncoding];
}
-(NSArray*)componentsSeparatedBy:(NSData*)separator fileContentType:(NSData*)fileContentType
{
    //return datatype is array,because a param name may be repeated
    
    NSMutableArray *components=[NSMutableArray array];
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
        
        NSRange formDataPartNameRange=[dataChunk rangeOfData:formDataPartName options:0 range:NSMakeRange(0,38)];
        
        if (!formDataPartNameRange.length) break;
        
        [dataChunk replaceBytesInRange:NSMakeRange(0,38) withBytes:NULL length:0];
        NSString *string = [[NSString alloc]initWithData:dataChunk encoding:NSUTF8StringEncoding];
        
        NSRange fileContentTypeRange=[dataChunk rangeOfData:fileContentType options:0 range:NSMakeRange(0,[dataChunk length])];
        if (fileContentTypeRange.location != NSNotFound)
        {
            //find param name
            NSRange doubleQuotesRange=[dataChunk rangeOfData:doubleQuotes options:0 range:NSMakeRange(0,[dataChunk length])];
            NSString *name=[[NSString alloc]initWithData:[dataChunk subdataWithRange:NSMakeRange(0,doubleQuotesRange.location)] encoding:NSUTF8StringEncoding];
            //base64 file
            [dataChunk replaceBytesInRange:NSMakeRange(0,fileContentTypeRange.location + fileContentTypeRange.length) withBytes:NULL length:0];
            [components addObject:[NSURLQueryItem queryItemWithName:name value:[dataChunk base64EncodedStringWithOptions:0]]];
        }
        else
        {
            NSString *string = [[NSString alloc]initWithData:dataChunk encoding:NSUTF8StringEncoding];
            NSArray *nameValue=[string componentsSeparatedByString:@"\"\r\n\r\n"];
            [components addObject:[NSURLQueryItem queryItemWithName:nameValue[0] value:nameValue[1]]];
        }
        
        componentStart=separatorRange.location + separatorRange.length + 2;//2...0D0A
        containerRange.location=componentStart;
        containerRange.length=self.length - componentStart;

        separatorRange=[self rangeOfData:separator options:0 range:containerRange];
    }
    return [NSArray arrayWithArray:components];
}
@end
