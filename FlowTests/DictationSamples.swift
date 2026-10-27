import Foundation

/// Realistic dictations for the real-model latency benchmark and the incremental-transcription accuracy check.
/// `[[slnc N]]` is a `say` pause of N ms: short ones between phrases, longer "thinking" pauses mid-sentence.
enum DictationSamples {
    struct Sample: Sendable {
        let name: String
        let voice: String
        let text: String

        /// The words `say` speaks, without the pause commands (the reference for word error rate).
        var spokenText: String { text.replacing(#/\[\[[^\]]*\]\]/#, with: " ") }
    }

    /// One per benchmark length (≈ 3 / 10 / 20 / 40 s).
    static let byLength: [Sample] = [
        Sample(name: "3s", voice: "Samantha", text: "Can you make the header sticky on mobile?"),
        Sample(name: "10s", voice: "Samantha", text: """
            Okay so the login page is broken on Safari. [[slnc 600]] When I click sign in, \
            nothing happens and the console shows a CORS error.
            """),
        Sample(name: "20s", voice: "Samantha", text: """
            I want you to refactor the payment service. [[slnc 700]] Split the Stripe webhook handler \
            into its own file, [[slnc 500]] add tests for the refund path, [[slnc 900]] and make sure we \
            log every failed charge with the customer ID. Don't change the public API.
            """),
        Sample(name: "40s", voice: "Samantha", text: """
            Here's the plan for tomorrow's demo. [[slnc 800]] First, we show the new onboarding flow \
            on an iPhone, [[slnc 600]] starting from a fresh install. Then we switch to the dashboard \
            [[slnc 1200]] and walk through the weekly report, especially the churn chart that Maria rebuilt \
            last week. [[slnc 700]] If there's time, we open the settings page and turn on dark mode, \
            [[slnc 500]] because people always ask about it. Finally, I'll take questions, [[slnc 900]] \
            but let's keep it under thirty minutes in total so the sales team can join their next call.
            """),
    ]

    /// Multi-sentence dictations (≈ 10–60 s) with pauses mid-sentence, across voices and accents.
    static let accuracySet: [Sample] = byLength.dropFirst() + [
        Sample(name: "email-daniel", voice: "Daniel", text: """
            Write a short email to the landlord. [[slnc 700]] Say that the boiler stopped working on \
            Sunday evening [[slnc 1100]] and we've had no hot water since. Ask if someone can come \
            round on Thursday morning, [[slnc 600]] ideally before ten, and mention that we're happy \
            to let them in with the spare key.
            """),
        Sample(name: "bug-karen", voice: "Karen", text: """
            There's a race condition in the upload queue. [[slnc 800]] When two files finish at the \
            same time, [[slnc 500]] the progress bar jumps back to zero [[slnc 1300]] and the second \
            file is uploaded twice. I think the problem is that we reset the counter inside the \
            completion handler [[slnc 600]] instead of after the whole batch. Can you find where that \
            happens and suggest a fix? [[slnc 700]] Please keep the change small, because we're \
            shipping on Friday.
            """),
        Sample(name: "notes-moira", voice: "Moira", text: """
            Summarise these meeting notes for the team. [[slnc 900]] We agreed to move the launch \
            to the fourteenth of March, [[slnc 600]] mostly because the translations aren't ready. \
            Priya will own the German and French copy, [[slnc 700]] Tom will handle the app store \
            screenshots, [[slnc 1500]] and I'll talk to legal about the new privacy wording. \
            [[slnc 800]] We also decided to drop the referral feature from this release [[slnc 500]] \
            and revisit it in the summer. The budget stays the same, [[slnc 700]] but marketing \
            wants a bigger share for the first two weeks after launch. [[slnc 600]] Next check-in \
            is Tuesday at three.
            """),
        Sample(name: "prompt-samantha", voice: "Samantha", text: """
            Act as a senior iOS engineer reviewing my pull request. [[slnc 800]] Focus on memory \
            leaks, [[slnc 400]] retain cycles in closures, [[slnc 400]] and anything that touches \
            the main thread. [[slnc 1200]] Don't comment on naming or formatting, [[slnc 500]] \
            we have a linter for that. For each problem, quote the line, [[slnc 600]] explain why \
            it matters in one sentence, [[slnc 700]] and suggest the smallest possible fix. \
            [[slnc 900]] If everything looks fine, just say so. Don't invent issues. [[slnc 1000]] \
            At the end, give me a rating from one to five for how ready this is to merge, \
            [[slnc 500]] and list anything you'd want tested by hand before we ship it to TestFlight.
            """),
    ]
}
