//
//  NSData+ZIP.h
//  httpdicom
//
//  Created by jacquesfauquex on 20171216.
//  Copyright © 2017 ridi.salud.uy. All rights reserved.
//

#import <Foundation/Foundation.h>

#define DEFAULT_POLYNOMIAL 0xEDB88320L
#define DEFAULT_SEED       0xFFFFFFFFL

@interface NSData (ZIP)

-(uint32_t) crc32;
-(uint32_t) crc32WithSeed:(uint32_t)seed;
-(uint32_t) crc32UsingPolynomial:(uint32_t)poly;
-(uint32_t) crc32WithSeed:(uint32_t)seed usingPolynomial:(uint32_t)poly;

@end
