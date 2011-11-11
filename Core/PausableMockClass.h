//
//  PausableMockClass.h
//  Talkto
//
//  Created by pushpraj agrawal on 11/11/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

/*
 Subclasses of this class can be paused/resumed, which makes any method defined in the class inaccessible.
 a Paused object behaves like belonging to this class. 
 
 NSObject methods on paused object would behave in primitive form and should be avoided.
 */

@interface PausableMockClass : NSObject

@property (assign, nonatomic) Class originalClass;
@property (assign, nonatomic) BOOL isPaused;

- (void)pause;
- (void)resume;


@end
