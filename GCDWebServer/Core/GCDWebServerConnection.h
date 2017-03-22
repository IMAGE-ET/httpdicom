#import "GCDWebServer.h"

/*
 Copyright (c) 2012-2015, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


@class GCDWebServerHandler;

/**
 *  The GCDWebServerConnection class is instantiated by GCDWebServer to handle
 *  each new HTTP connection. Each instance stays alive until the connection is
 *  closed.
 */
@interface GCDWebServerConnection : NSObject

/**
 *  Returns the GCDWebServer that owns the connection.
 */
@property(nonatomic, readonly) GCDWebServer* server;


/**
 *  Returns the address of the local peer (i.e. server) of the connection
 *  as a raw "struct sockaddr".
 */
@property(nonatomic, readonly) NSData* localAddressData;

/**
 *  Returns the address of the local peer (i.e. server) of the connection
 *  as a string.
 */
@property(nonatomic, readonly) NSString* localAddressString;

/**
 *  Returns the address of the remote peer (i.e. client) of the connection
 *  as a raw "struct sockaddr".
 */
@property(nonatomic, readonly) NSData* remoteAddressData;

/**
 *  Returns the address of the remote peer (i.e. client) of the connection
 *  as a string.
 */
@property(nonatomic, readonly) NSString* remoteAddressString;

/**
 *  Returns the total number of bytes received from the remote peer (i.e. client)
 *  so far.
 */
@property(nonatomic, readonly) NSUInteger totalBytesRead;

/**
 *  Returns the total number of bytes sent to the remote peer (i.e. client) so far.
 */
@property(nonatomic, readonly) NSUInteger totalBytesWritten;

/**
 *  This method is called if any error happens while validing or processing
 *  the request or if no GCDWebServerResponse was generated during processing.
 *
 *  @warning If the request was invalid (e.g. the HTTP headers were malformed),
 *  the "request" argument will be nil.
 */
- (void)abortRequest:(GCDWebServerRequest*)request withStatusCode:(NSInteger)statusCode;

@end
