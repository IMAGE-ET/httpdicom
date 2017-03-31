#import "RSResponse.h"

#import <zlib.h>
#import "ODLog.h"

#define kZlibErrorDomain @"ZlibErrorDomain"
#define kGZipInitialBufferSize (256 * 1024)

@interface RSBodyEncoder : NSObject <RSBodyReader>
- (id)initWithResponse:(RSResponse*)response reader:(id<RSBodyReader>)reader;
@end

@interface RSGZipEncoder : RSBodyEncoder
@end

@interface RSBodyEncoder () {
@private
  RSResponse* __unsafe_unretained _response;
  id<RSBodyReader> __unsafe_unretained _reader;
}
@end

@implementation RSBodyEncoder

- (id)initWithResponse:(RSResponse*)response reader:(id<RSBodyReader>)reader {
  if ((self = [super init])) {
    _response = response;
    _reader = reader;
  }
  return self;
}

- (BOOL)open:(NSError**)error {
  return [_reader open:error];
}

- (NSData*)readData:(NSError**)error {
  return [_reader readData:error];
}

- (void)close {
  [_reader close];
}

@end

@interface RSGZipEncoder () {
@private
  z_stream _stream;
  BOOL _finished;
}
@end

@implementation RSGZipEncoder

- (id)initWithResponse:(RSResponse*)response reader:(id<RSBodyReader>)reader {
  if ((self = [super initWithResponse:response reader:reader])) {
    response.contentLength = NSUIntegerMax;  // Make sure "Content-Length" header is not set since we don't know it
    [response setValue:@"gzip" forAdditionalHeader:@"Content-Encoding"];
  }
  return self;
}

- (BOOL)open:(NSError**)error {
  int result = deflateInit2(&_stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
  if (result != Z_OK) {
    if (error) {
      *error = [NSError errorWithDomain:kZlibErrorDomain code:result userInfo:nil];
    }
    return NO;
  }
  if (![super open:error]) {
    deflateEnd(&_stream);
    return NO;
  }
  return YES;
}

- (NSData*)readData:(NSError**)error {
  NSMutableData* encodedData;
  if (_finished) {
    encodedData = [[NSMutableData alloc] init];
  } else {
    encodedData = [[NSMutableData alloc] initWithLength:kGZipInitialBufferSize];
    if (encodedData == nil) {
      return nil;
    }
    NSUInteger length = 0;
    do {
      NSData* data = [super readData:error];
      if (data == nil) {
        return nil;
      }
      _stream.next_in = (Bytef*)data.bytes;
      _stream.avail_in = (uInt)data.length;
      while (1) {
        NSUInteger maxLength = encodedData.length - length;
        _stream.next_out = (Bytef*)((char*)encodedData.mutableBytes + length);
        _stream.avail_out = (uInt)maxLength;
        int result = deflate(&_stream, data.length ? Z_NO_FLUSH : Z_FINISH);
        if (result == Z_STREAM_END) {
          _finished = YES;
        } else if (result != Z_OK) {
          if (error) {
            *error = [NSError errorWithDomain:kZlibErrorDomain code:result userInfo:nil];
          }
          return nil;
        }
        length += maxLength - _stream.avail_out;
        if (_stream.avail_out > 0) {
          break;
        }
        encodedData.length = 2 * encodedData.length;  // zlib has used all the output buffer so resize it and try again in case more data is available
      }
    } while (length == 0);  // Make sure we don't return an empty NSData if not in finished state
    encodedData.length = length;
  }
  return encodedData;
}

- (void)close {
  deflateEnd(&_stream);
  [super close];
}

@end

@interface RSResponse () {
@private
  NSString* _type;
  NSUInteger _length;
  NSInteger _status;
  NSUInteger _maxAge;
  NSDate* _lastModified;
  NSString* _eTag;
  NSMutableDictionary* _headers;
  BOOL _chunked;
  BOOL _gzipped;
  
  BOOL _opened;
  NSMutableArray* _encoders;
  id<RSBodyReader> __unsafe_unretained _reader;
}
@end

@implementation RSResponse

@synthesize contentType=_type, contentLength=_length, statusCode=_status, cacheControlMaxAge=_maxAge, lastModifiedDate=_lastModified, eTag=_eTag,
            gzipContentEncodingEnabled=_gzipped, additionalHeaders=_headers;

+ (instancetype)response {
  return [[[self class] alloc] init];
}

- (instancetype)init {
  if ((self = [super init])) {
    _type = nil;
    _length = NSUIntegerMax;
    _status = 200;//OK
    _maxAge = 0;
    _headers = [[NSMutableDictionary alloc] init];
    _encoders = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)setValue:(NSString*)value forAdditionalHeader:(NSString*)header {
  [_headers setValue:value forKey:header];
}

- (BOOL)hasBody {
  return _type ? YES : NO;
}

- (BOOL)usesChunkedTransferEncoding {
  return (_type != nil) && (_length == NSUIntegerMax);
}

- (BOOL)open:(NSError**)error {
  return YES;
}

- (NSData*)readData:(NSError**)error {
  return [NSData data];
}

- (void)close {
  ;
}

- (void)prepareForReading {
  _reader = self;
  if (_gzipped) {
    RSGZipEncoder* encoder = [[RSGZipEncoder alloc] initWithResponse:self reader:_reader];
    [_encoders addObject:encoder];
    _reader = encoder;
  }
}

- (BOOL)performOpen:(NSError**)error {
  if (_opened) {
    return NO;
  }
  _opened = YES;
  return [_reader open:error];
}

- (void)performReadDataWithCompletion:(RSBodyReaderCompletionBlock)block {
  if ([_reader respondsToSelector:@selector(asyncReadDataWithCompletion:)]) {
    [_reader asyncReadDataWithCompletion:[block copy]];
  } else {
    NSError* error = nil;
    NSData* data = [_reader readData:&error];
    block(data, error);
  }
}

- (void)performClose {
  [_reader close];
}

- (NSString*)description {
  NSMutableString* description = [NSMutableString stringWithFormat:@"Status Code = %i", (int)_status];
  if (_type) {
    [description appendFormat:@"\nContent Type = %@", _type];
  }
  if (_length != NSUIntegerMax) {
    [description appendFormat:@"\nContent Length = %lu", (unsigned long)_length];
  }
  [description appendFormat:@"\nCache Control Max Age = %lu", (unsigned long)_maxAge];
  if (_lastModified) {
    [description appendFormat:@"\nLast Modified Date = %@", _lastModified];
  }
  if (_eTag) {
    [description appendFormat:@"\nETag = %@", _eTag];
  }
  if (_headers.count) {
    [description appendString:@"\n"];
    for (NSString* header in [[_headers allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      [description appendFormat:@"\n%@: %@", header, [_headers objectForKey:header]];
    }
  }
  return description;
}

@end

@implementation RSResponse (Extensions)

+ (instancetype)responseWithStatusCode:(NSInteger)statusCode {
  return [[self alloc] initWithStatusCode:statusCode];
}

+ (instancetype)responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  return [[self alloc] initWithRedirect:location permanent:permanent];
}

- (instancetype)initWithStatusCode:(NSInteger)statusCode {
  if ((self = [self init])) {
    self.statusCode = statusCode;
  }
  return self;
}

- (instancetype)initWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  if ((self = [self init])) {
    self.statusCode = permanent ? 301 : 307;//?MovedPermanently:TemporaryRedirect
    [self setValue:[location absoluteString] forAdditionalHeader:@"Location"];
  }
  return self;
}

@end
