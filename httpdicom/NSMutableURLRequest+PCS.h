//
//  NSMutableURLRequest+PCS.h
//  httpdicom
//
//  Created by jacquesfauquex on 2017129.
//  Copyright © 2017 ridi.salud.uy. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableURLRequest (PCS)

+(id)PUTpatient:(NSString*)URLString name:(NSString*)name pid:(NSString*)pid issuer:(NSString*)issuer birthdate:(NSString*)birthdate sex:(NSString*)sex contentType:(NSString*)contentType timeout:(NSTimeInterval)timeout;

+(id)POSTmwlitem:(NSString*)URLString CS:(NSString*)CS aet:(NSString*)aet DA:(NSString*)DA TM:(NSString*)TM modality:(NSString*)modality accessionNumber:(NSString*)accessionNumber status:(NSString*)status procCode:(NSString*)procCode procScheme:(NSString*)procScheme procMeaning:(NSString*)procMeaning priority:(NSString*)priority name:(NSString*)name pid:(NSString*)pid issuer:(NSString*)issuer birthdate:(NSString*)birthdate sex:(NSString*)sex contentType:(NSString*)contentType timeout:(NSTimeInterval)timeout;

@end
