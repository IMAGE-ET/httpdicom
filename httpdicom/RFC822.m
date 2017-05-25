#import "RFC822.h"
static NSDateFormatter *RFC822DateFormatter;
@implementation RFC822

+ (void) initialize {
    RFC822DateFormatter = [[NSDateFormatter alloc] init];
    RFC822DateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    RFC822DateFormatter.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    RFC822DateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

+(NSDate*)dateFromString:(NSString*)string
{
    return [RFC822DateFormatter dateFromString:string];
}

+(NSString*)stringFromDate:(NSDate*)date
{
    return [RFC822DateFormatter stringFromDate:date];
}

@end
