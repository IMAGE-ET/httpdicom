//
//  URLSessionDataTask.h
//  httpdicom
//
//  Created by jacquesfauquex on 2016-11-01.
//  Copyright © 2016 ridi.salud.uy. All rights reserved.
//
@import Foundation;

typedef void (^CompletionHandler)();

@interface URLSessionDataTask : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
{
    NSMutableArray *dataPile;
    NSData *dataEnd;
}

//, NSURLSessionDownloadDelegate, NSURLSessionStreamDelegate
@property NSMutableDictionary <NSString *, CompletionHandler>*completionHandlers;

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error;

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data;
/*
 Because the NSData object is often pieced together from a number of different data objects, whenever possible, use NSData’s enumerateByteRangesUsingBlock: method to iterate through the data rather than using the bytes method (which flattens the NSData object into a single memory block).
 
 This delegate method may be called more than once, and each call provides only data received since the previous call. The app is responsible for accumulating this data if needed.

-(id)proxySession:(NSURLSession*)session URI:(NSString*)urlString contentType:(NSString*)contentType;
*/


@end
