//
//  URLSessionDataTask.m
//  httpdicom
//
//  Created by jacquesfauquex on 2016-11-01.
//  Copyright © 2016 ridi.salud.uy. All rights reserved.
//

#import "URLSessionDataTask.h"
#import "RSStreamedResponse.h"

@implementation URLSessionDataTask

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    if (data.length) [dataPile addObject:data];
    else [dataPile addObject:dataEnd];    
}

-(id)proxySession:(NSURLSession*)session URI:(NSString*)urlString contentType:(NSString*)contentType
{
    dataPile=[NSMutableArray array];
    uuid_t uuid;
    [[NSUUID UUID]getUUIDBytes:uuid];
    dataEnd=[NSData dataWithBytes:uuid length:16];
    __block NSURLSessionDataTask * const __URLSessionDataTask = [session dataTaskWithURL:[NSURL URLWithString:urlString]];
    //__block bool __shouldExit = false;
    [__URLSessionDataTask resume];
    RSStreamedResponse* response = [RSStreamedResponse responseWithContentType:contentType asyncStreamBlock:^(RSBodyReaderCompletionBlock completionBlock){
        //while (!__shouldExit && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])
        
        if ([dataPile count]>0)
        {
            if([dataPile[0] isEqualToData:dataEnd]) completionBlock([NSData data], nil);
            else completionBlock(dataPile[0], nil);
            [dataPile removeObjectAtIndex:0];
        }
        else completionBlock(nil,nil);
      }];
    return response;
}

@end
