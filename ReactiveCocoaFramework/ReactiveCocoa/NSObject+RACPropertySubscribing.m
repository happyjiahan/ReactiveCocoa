//
//  NSObject+RACPropertySubscribing.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/2/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACPropertySubscribing.h"
#import "EXTScope.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACKVOWrapper.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACKVOTrampoline.h"
#import "RACSubscriber.h"
#import "RACSignal+Operations.h"
#import <libkern/OSAtomic.h>

@interface NSObject (RACPropertySubscribingPrivate)

// Creates a signal that calls block every time the key path changes, and sends
// the returns value to it's subscribers.
- (RACSignal *)rac_signalForKeyPath:(NSString *)keyPath observer:(NSObject *)observer block:(id(^)(id value, NSDictionary *change))block;

@end

@implementation NSObject (RACPropertySubscribing)

- (RACSignal *)rac_valuesForKeyPath:(NSString *)keyPath observer:(NSObject *)observer {
  return [[self rac_signalForKeyPath:keyPath observer:observer block:^id(id value, NSDictionary *change) {
		return value;
	}] setNameWithFormat:@"RACObserve(%@, %@)", self.rac_description, keyPath];
}

- (RACSignal *)rac_changesForKeyPath:(NSString *)keyPath observer:(NSObject *)observer {
  return [[self rac_signalForKeyPath:keyPath observer:observer block:^id(id value, NSDictionary *change) {
		return change;
	}] setNameWithFormat:@"-[%@ rac_changesForKeyPath:%@]", self.rac_description, keyPath];
}

- (RACSignal *)rac_signalForKeyPath:(NSString *)keyPath observer:(NSObject *)observer block:(id (^)(id, NSDictionary *))block {
	__block volatile uint32_t deallocFlag = 0;
	RACDisposable *deallocFlagDisposable = [RACDisposable disposableWithBlock:^{
		OSAtomicOr32Barrier(1, &deallocFlag);
	}];
	RACCompoundDisposable *observerDisposable = observer.rac_deallocDisposable;
	RACCompoundDisposable *objectDisposable = self.rac_deallocDisposable;
	[observerDisposable addDisposable:deallocFlagDisposable];
	[objectDisposable addDisposable:deallocFlagDisposable];

	@unsafeify(self, observer);
	return [RACSignal createSignal:^ RACDisposable * (id<RACSubscriber> subscriber) {
		@strongify(self, observer);
		if (deallocFlag == 1) {
			[subscriber sendCompleted];
			return nil;
		}

		id initialValue = [self valueForKeyPath:keyPath];
		NSDictionary *initialChange = @{
			NSKeyValueChangeKindKey: @(NSKeyValueChangeSetting),
			NSKeyValueChangeNewKey: initialValue ?: NSNull.null
		};
		[subscriber sendNext:block(initialValue, initialChange)];
		RACDisposable *observationDisposable = [self rac_addObserver:observer forKeyPath:keyPath willChangeBlock:nil didChangeBlock:^(id value, NSDictionary *change) {
			[subscriber sendNext:block(value, change)];
		}];

		@weakify(subscriber);
		RACDisposable *deallocDisposable = [RACDisposable disposableWithBlock:^{
			@strongify(subscriber);
			[observationDisposable dispose];
			[subscriber sendCompleted];
		}];

		[observer.rac_deallocDisposable addDisposable:deallocDisposable];
		[self.rac_deallocDisposable addDisposable:deallocDisposable];

		return [RACDisposable disposableWithBlock:^{
			[observerDisposable removeDisposable:deallocFlagDisposable];
			[objectDisposable removeDisposable:deallocFlagDisposable];
			[observerDisposable removeDisposable:deallocDisposable];
			[objectDisposable removeDisposable:deallocDisposable];
			[observationDisposable dispose];
		}];
	}];
}

@end

static RACSignal *signalWithoutChangesFor(Class class, NSObject *object, NSString *keyPath, NSKeyValueObservingOptions options, NSObject *observer) {
	NSCParameterAssert(object != nil);
	NSCParameterAssert(keyPath != nil);
	NSCParameterAssert(observer != nil);

	keyPath = [keyPath copy];

	@unsafeify(object);

	return [[class
					 rac_signalWithChangesFor:object keyPath:keyPath options:options observer:observer]
					map:^(NSDictionary *change) {
						@strongify(object);
						return [object valueForKeyPath:keyPath];
					}];
}

@implementation NSObject (RACPropertySubscribingDeprecated)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

+ (RACSignal *)rac_signalFor:(NSObject *)object keyPath:(NSString *)keyPath observer:(NSObject *)observer {
	return signalWithoutChangesFor(self, object, keyPath, 0, observer);
}

+ (RACSignal *)rac_signalWithStartingValueFor:(NSObject *)object keyPath:(NSString *)keyPath observer:(NSObject *)observer {
	return signalWithoutChangesFor(self, object, keyPath, NSKeyValueObservingOptionInitial, observer);
}

+ (RACSignal *)rac_signalWithChangesFor:(NSObject *)object keyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options observer:(NSObject *)observer {
	@unsafeify(observer, object);
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {

		@strongify(observer, object);
		RACKVOTrampoline *KVOTrampoline = [object rac_addObserver:observer forKeyPath:keyPath options:options block:^(id target, id observer, NSDictionary *change) {
			[subscriber sendNext:change];
		}];

		@weakify(subscriber);
		RACDisposable *deallocDisposable = [RACDisposable disposableWithBlock:^{
			@strongify(subscriber);
			[KVOTrampoline dispose];
			[subscriber sendCompleted];
		}];

		[observer.rac_deallocDisposable addDisposable:deallocDisposable];
		[object.rac_deallocDisposable addDisposable:deallocDisposable];

		RACCompoundDisposable *observerDisposable = observer.rac_deallocDisposable;
		RACCompoundDisposable *objectDisposable = object.rac_deallocDisposable;
		return [RACDisposable disposableWithBlock:^{
			[observerDisposable removeDisposable:deallocDisposable];
			[objectDisposable removeDisposable:deallocDisposable];
			[KVOTrampoline dispose];
		}];
	}] setNameWithFormat:@"RACAble(%@, %@)", object.rac_description, keyPath];
}

- (RACSignal *)rac_signalForKeyPath:(NSString *)keyPath observer:(NSObject *)observer {
	return [self.class rac_signalFor:self keyPath:keyPath observer:observer];
}

- (RACSignal *)rac_signalWithStartingValueForKeyPath:(NSString *)keyPath observer:(NSObject *)observer {
	return [self.class rac_signalWithStartingValueFor:self keyPath:keyPath observer:observer];
}

- (RACDisposable *)rac_deriveProperty:(NSString *)keyPath from:(RACSignal *)signal {
	return [signal setKeyPath:keyPath onObject:self];
}

#pragma clang diagnostic pop

@end
