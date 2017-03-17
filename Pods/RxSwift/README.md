<img src="assets/Rx_Logo_M.png" alt="Miss Electric Eel 2016" width="36" height="36"> RxSwift: ReactiveX for Swift
======================================

[![Travis CI](https://travis-ci.org/ReactiveX/RxSwift.svg?branch=master)](https://travis-ci.org/ReactiveX/RxSwift) ![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-333333.svg) ![pod](https://img.shields.io/cocoapods/v/RxSwift.svg) [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) [![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

## About Rx

**:warning: This readme describes RxSwift 3.0 version that requires Swift 3.0.**

**:warning: If you are looking for Swift 2.3 compatible version, please take a look at RxSwift ~> 2.0 versions and [swift-2.3](https://github.com/ReactiveX/RxSwift/tree/rxswift-2.0) branch.**

Rx is a [generic abstraction of computation](https://youtu.be/looJcaeboBY) expressed through `Observable<Element>` interface.

This is a Swift version of [Rx](https://github.com/Reactive-Extensions/Rx.NET).

It tries to port as many concepts from the original version as possible, but some concepts were adapted for more pleasant and performant integration with iOS/macOS environment.

Cross platform documentation can be found on [ReactiveX.io](http://reactivex.io/).

Like the original Rx, its intention is to enable easy composition of asynchronous operations and event/data streams.

KVO observing, async operations and streams are all unified under [abstraction of sequence](Documentation/GettingStarted.md#observables-aka-sequences). This is the reason why Rx is so simple, elegant and powerful.

## I came here because I want to ...

###### ... understand

* [why use rx?](Documentation/Why.md)
* [the basics, getting started with RxSwift](Documentation/GettingStarted.md)
* [units](Documentation/Units.md) - what is `Driver`, `ControlProperty`, and `Variable` ... and why do they exist?
* [testing](Documentation/UnitTests.md)
* [tips and common errors](Documentation/Tips.md)
* [debugging](Documentation/GettingStarted.md#debugging)
* [the math behind Rx](Documentation/MathBehindRx.md)
* [what are hot and cold observable sequences?](Documentation/HotAndColdObservables.md)

###### ... install

* Integrate RxSwift/RxCocoa with my app. [Installation Guide](#installation)

###### ... hack around

* with the example app. [Running Example App](Documentation/ExampleApp.md)
* with operators in playgrounds. [Playgrounds](Documentation/Playgrounds.md)

###### ... interact

* All of this is great, but it would be nice to talk with other people using RxSwift and exchange experiences. <br />[![Slack channel](http://rxswift-slack.herokuapp.com/badge.svg)](http://slack.rxswift.org) [Join Slack Channel](http://rxswift-slack.herokuapp.com)
* Report a problem using the library. [Open an Issue With Bug Template](.github/ISSUE_TEMPLATE.md)
* Request a new feature. [Open an Issue With Feature Request Template](Documentation/NewFeatureRequestTemplate.md)


###### ... compare

* [with other libraries](Documentation/ComparisonWithOtherLibraries.md).


###### ... find compatible

* libraries from [RxSwiftCommunity](https://github.com/RxSwiftCommunity).
* [Pods using RxSwift](https://cocoapods.org/?q=uses%3Arxswift).

###### ... see the broader vision

* Does this exist for Android? [RxJava](https://github.com/ReactiveX/RxJava)
* Where is all of this going, what is the future, what about reactive architectures, how do you design entire apps this way? [Cycle.js](https://github.com/cyclejs/cycle-core) - this is javascript, but [RxJS](https://github.com/Reactive-Extensions/RxJS) is javascript version of Rx.

## Usage

<table>
  <tr>
    <th width="30%">Here's an example</th>
    <th width="30%">In Action</th>
  </tr>
  <tr>
    <td>Define search for GitHub repositories ...</td>
    <th rowspan="9"><img src="https://raw.githubusercontent.com/kzaher/rxswiftcontent/master/GithubSearch.gif"></th>
  </tr>
  <tr>
    <td><div class="highlight highlight-source-swift"><pre>
let searchResults = searchBar.rx.text.orEmpty
    .throttle(0.3, scheduler: MainScheduler.instance)
    .distinctUntilChanged()
    .flatMapLatest { query -> Observable<[Repository]> in
        if query.isEmpty {
            return .just([])
        }

        return searchGitHub(query)
            .catchErrorJustReturn([])
    }
    .observeOn(MainScheduler.instance)</pre></div></td>
  </tr>
  <tr>
    <td>... then bind the results to your tableview</td>
  </tr>
  <tr>
    <td width="30%"><div class="highlight highlight-source-swift"><pre>
searchResults
    .bindTo(tableView.rx.items(cellIdentifier: "Cell")) {
        (index, repository: Repository, cell) in
        cell.textLabel?.text = repository.name
        cell.detailTextLabel?.text = repository.url
    }
    .addDisposableTo(disposeBag)</pre></div></td>
  </tr>
</table>


## Requirements

* Xcode 8.0
* Swift 3.0

## Installation

Rx doesn't contain any external dependencies.

These are currently the supported options:

### Manual

Open Rx.xcworkspace, choose `RxExample` and hit run. This method will build everything and run the sample app

### [CocoaPods](https://guides.cocoapods.org/using/using-cocoapods.html)

**Tested with `pod --version`: `1.1.1`**

```
# Podfile
use_frameworks!

target 'YOUR_TARGET_NAME' do
    pod 'RxSwift',    '~> 3.0'
    pod 'RxCocoa',    '~> 3.0'
end

# RxTests and RxBlocking make the most sense in the context of unit/integration tests
target 'YOUR_TESTING_TARGET' do
    pod 'RxBlocking', '~> 3.0'
    pod 'RxTest',     '~> 3.0'
end
```

Replace `YOUR_TARGET_NAME` and then, in the `Podfile` directory, type:

```
$ pod install
```

### [Carthage](https://github.com/Carthage/Carthage)

**Tested with `carthage version`: `0.18.1`**

Add this to `Cartfile`

```
github "ReactiveX/RxSwift" ~> 3.0
```

```
$ carthage update
```

### [Swift Package Manager](https://github.com/apple/swift-package-manager)

**Tested with `swift build --version`: `3.0.0 (swiftpm-19)`**

Create a `Package.swift` file.

```
import PackageDescription

let package = Package(
    name: "RxTestProject",
    targets: [],
    dependencies: [
        .Package(url: "https://github.com/ReactiveX/RxSwift.git", majorVersion: 3)
    ]
)
```

```
$ swift build
```

### Manually using git submodules

* Add RxSwift as a submodule

```
$ git submodule add git@github.com:ReactiveX/RxSwift.git
```

* Drag `Rx.xcodeproj` into Project Navigator
* Go to `Project > Targets > Build Phases > Link Binary With Libraries`, click `+` and select `RxSwift-[Platform]` and `RxCocoa-[Platform]` targets


## References

* [http://reactivex.io/](http://reactivex.io/)
* [Reactive Extensions GitHub (GitHub)](https://github.com/Reactive-Extensions)
* [Erik Meijer (Wikipedia)](http://en.wikipedia.org/wiki/Erik_Meijer_%28computer_scientist%29)
* [Expert to Expert: Brian Beckman and Erik Meijer - Inside the .NET Reactive Framework (Rx) (video)](https://youtu.be/looJcaeboBY)
* [Reactive Programming Overview (Jafar Husain from Netflix)](https://www.youtube.com/watch?v=dwP1TNXE6fc)
* [Subject/Observer is Dual to Iterator (paper)](http://csl.stanford.edu/~christos/pldi2010.fit/meijer.duality.pdf)
* [Rx standard sequence operators visualized (visualization tool)](http://rxmarbles.com/)
* [Haskell](https://www.haskell.org/)
