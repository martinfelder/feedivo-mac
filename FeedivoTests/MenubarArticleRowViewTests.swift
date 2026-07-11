import Testing
@testable import Feedivo

struct MenubarArticleRowViewTests {

    @Test func showsThumbnailIstWahrBeiGueltigerImageURL() {
        #expect(MenubarArticleRowView.showsThumbnail(imageURL: "https://example.com/image.jpg") == true)
    }

    @Test func showsThumbnailIstFalschOhneImageURL() {
        #expect(MenubarArticleRowView.showsThumbnail(imageURL: nil) == false)
    }

    @Test func showsThumbnailIstFalschBeiUngueltigerURL() {
        #expect(MenubarArticleRowView.showsThumbnail(imageURL: "") == false)
    }
}
