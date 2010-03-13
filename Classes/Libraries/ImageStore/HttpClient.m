// Created by Satoshi Nakagawa.
// You can redistribute it and/or modify it under the new BSD license.

#import "HttpClient.h"
#import "StringHelper.h"

#define HTTP_CLIENT_TIMEOUT 180.0

@implementation HttpClient

@synthesize delegate;
@synthesize userAgent;

- (id)init
{
	if (self = [super init]) {
		;
	}
	return self;
}

- (id)initWithDelegate:(id)aDelegate
{
	if ([self init]) {
		delegate = aDelegate;
	}
	return self;
}

- (void)dealloc
{
	[self cancel];
	[userAgent release];
	[super dealloc];
}

- (void)cancel
{
	if (conn) {
		[conn cancel];
		[conn autorelease];
	}
	[response autorelease];
	[buf autorelease];
	
	conn = nil;
	response = nil;
	buf = nil;
}

- (NSString*)buildParameters:(NSDictionary*)params
{
	NSMutableString* s = [NSMutableString string];
	if (params) {
		NSEnumerator* e = [params keyEnumerator];
		NSString* key;
		while (key = (NSString*)[e nextObject]) {
			NSString* value = [[params objectForKey:key] encodeAsURIComponent];
			[s appendFormat:@"%@=%@&", key, value];
		}
		if (s.length > 0) [s deleteCharactersInRange:NSMakeRange(s.length-1, 1)];
	}
	return s;
}

- (void)appendTo:(NSMutableData*)data string:(NSString *)string
{
	[data appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)buildMultiPartBody:(NSMutableData*)body params:(NSDictionary*)params boundary:(NSString*)boundary
{
	if (!params) {
		return;
	}
	NSEnumerator* e = [params keyEnumerator];
	NSString* key;
	
	while (key = (NSString*)[e nextObject]) {
		id value = [params objectForKey:key];
		
		[self appendTo:body string:[NSString stringWithFormat:@"--%@\r\n", boundary]];
		
		if ([value isKindOfClass:[NSString class]]) {
			NSString* string = (NSString*)value;
			[self appendTo:body string:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key]];
			[self appendTo:body string:[NSString stringWithFormat:@"%@\r\n", string]];
			
		} else if ([value isKindOfClass:[FilePart class]]) {
			FilePart* filePart = (FilePart*)value;
			[self appendTo:body string:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", key, filePart.filename]];
			[self appendTo:body string:@"Content-Type: application/octet-stream\r\n\r\n"];
			[body appendData:filePart.filedata];
			[self appendTo:body string:@"\r\n"];
		}
	}
	[self appendTo:body string:[NSString stringWithFormat:@"--%@--\r\n", boundary]];
}

- (void)get:(NSString*)url parameters:(NSDictionary*)params
{
	[self cancel];
	
	NSMutableString* fullUrl = [NSMutableString stringWithString:url];
	NSString* paramStr = [self buildParameters:params];
	if (paramStr.length > 0) {
		[fullUrl appendString:@"?"];
		[fullUrl appendString:paramStr];
	}
	
	NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullUrl]
													   cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
												   timeoutInterval:HTTP_CLIENT_TIMEOUT];
	
	if (userAgent) [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
	[req setHTTPShouldHandleCookies:YES];
	
	conn = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	buf = [NSMutableData new];
}

- (void)post:(NSString*)url parameters:(NSDictionary*)params
{
	[self cancel];
	
	NSData* body = [[self buildParameters:params] dataUsingEncoding:NSUTF8StringEncoding];
	
	NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
													   cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
												   timeoutInterval:HTTP_CLIENT_TIMEOUT];
	
	[req setHTTPMethod:@"POST"];
	if (userAgent) [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
	[req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[req setValue:[NSString stringWithFormat:@"%d", body.length] forHTTPHeaderField:@"Content-Length"];
	[req setHTTPBody:body];
	[req setHTTPShouldHandleCookies:YES];
	
	conn = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	buf = [NSMutableData new];
}

- (void)postMultiPart:(NSString*)url parameters:(NSDictionary*)params 
{
	[self cancel];

	NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
													   cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
												   timeoutInterval:HTTP_CLIENT_TIMEOUT];
	
	[req setHTTPMethod:@"POST"];
	if (userAgent) [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
	
	static NSString* boundary = @"--BOUNDARY";
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
	[req setValue:contentType forHTTPHeaderField:@"Content-type"];
	
	NSMutableData* body = [[NSMutableData alloc] init];
	[self buildMultiPartBody:body params:params boundary:boundary];
	[req setHTTPBody:body];	
	[req setHTTPShouldHandleCookies:YES];
	
	conn = [[NSURLConnection alloc] initWithRequest:req delegate:self];
	buf = [NSMutableData new];
}

- (BOOL)isActive
{
	return conn != nil;
}

- (void)connection:(NSURLConnection*)sender didReceiveResponse:(NSHTTPURLResponse*)aResponse
{
	[response release];
	response = [aResponse retain];
}

- (void)connection:(NSURLConnection*)sender didReceiveData:(NSData*)data
{
	[buf appendData:data];
}

- (void)connection:(NSURLConnection*)sender didFailWithError:(NSError*)error
{
	[self cancel];
	
	if ([delegate respondsToSelector:@selector(httpClientFailed:error:)]) {
		[delegate httpClientFailed:self error:error];
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection*)sender
{
	NSData* tmpBuf = buf;
	NSHTTPURLResponse* tmpResponse = response;
	
	[self cancel];
	
	if ([delegate respondsToSelector:@selector(httpClientSucceeded:response:data:)]) {
		[delegate httpClientSucceeded:self response:tmpResponse data:tmpBuf];
	}
}

@end

@implementation FilePart

@synthesize filename;
@synthesize filedata;

- (id)initWithFilename:(NSString*)aFilename filedata:(NSData*)aFiledata 
{
	if (self = [super init]) {
		self.filename = aFilename;
		self.filedata = aFiledata;
	}
	return self;
}

- (void)dealloc 
{
	[filename release];
	[filedata release];
	[super dealloc];
}

@end

