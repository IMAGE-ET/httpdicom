@import Foundation;

/**
 *  Converts a date into a string using RFC822 formatting.
 *  https://tools.ietf.org/html/rfc822#section-5
 *  https://tools.ietf.org/html/rfc1123#section-5.2.14
 */

// TODO: Handle RFC 850 and ANSI C's asctime() format

@interface RFC822 : NSObject
+(NSDate*)dateFromString:(NSString*)string;
+(NSString*)stringFromDate:(NSDate*)date;
@end
