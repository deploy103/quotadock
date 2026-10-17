import XCTest
#if canImport(QuotaDockStorage)
@testable import QuotaDockStorage
#else
@testable import QuotaDock
#endif

final class BillingContractTests: XCTestCase {
    func testCatalogOriginAndPlusOnlyOneMonthTrial() {
        let products = ["com.quotadock.app.plus.monthly", "com.quotadock.app.plus.annual",
                        "com.quotadock.app.pro.monthly", "com.quotadock.app.pro.annual"]
        XCTAssertEqual(Set(BillingPolicy.productIDs), Set(products))
        XCTAssertTrue(BillingPolicy.officialOrigin(URL(string: "https://usage.mvtp.cloud")!))
        for text in ["http://usage.mvtp.cloud", "https://usage.mvtp.cloud.evil.test", "https://example.com",
                     "https://usage.mvtp.cloud:444", "https://user@usage.mvtp.cloud",
                     "https://usage.mvtp.cloud/custom", "https://usage.mvtp.cloud?token=x"] {
            XCTAssertFalse(BillingPolicy.officialOrigin(URL(string: text)!))
        }
        for id in products + ["com.quotadock.app.plus.foreign"] {
            for eligible in [true, false] {
                for free in [true, false] {
                    for month in [true, false] {
                        for value in [1, 2] {
                            for count in [1, 2] {
                                let plus = id == products[0] || id == products[1]
                                XCTAssertEqual(BillingPolicy.offersTrial(productID: id, freeTrial: free,
                                    monthUnit: month, periodValue: value, periodCount: count, eligible: eligible),
                                    plus && eligible && free && month && value == 1 && count == 1)
                            }
                        }
                    }
                }
            }
        }
        XCTAssertFalse(BillingPolicy.mayPurchase(promisedTrial: true, currentTrial: false))
        XCTAssertTrue(BillingPolicy.mayPurchase(promisedTrial: true, currentTrial: true))
        XCTAssertTrue(BillingPolicy.mayPurchase(promisedTrial: false, currentTrial: false))
    }
}
