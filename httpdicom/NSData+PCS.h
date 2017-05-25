//
//  NSData+PCS.h
//  httpdicom
//
//  Created by jacquesfauquex on 2016-10-12.
//  Copyright © 2016 ridi.salud.uy. All rights reserved.
//

#import <Foundation/Foundation.h>

#define DEFAULT_POLYNOMIAL 0xEDB88320L
#define DEFAULT_SEED       0xFFFFFFFFL

@interface NSData (PCS)
+(NSData*)jsonpCallback:(NSString*)callback withDictionary:(NSDictionary*)dictionary;
+(NSData*)jsonpCallback:(NSString*)callback forDraw:(NSString*)draw withErrorString:(NSString*)error;

-(uint32_t) crc32;
-(uint32_t) crc32WithSeed:(uint32_t)seed;
-(uint32_t) crc32UsingPolynomial:(uint32_t)poly;
-(uint32_t) crc32WithSeed:(uint32_t)seed usingPolynomial:(uint32_t)poly;

@end
