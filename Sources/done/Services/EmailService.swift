import Vapor
import Smtp

struct EmailService: Sendable {
    let app: Application
    
    init(app: Application) {
        self.app = app
        // Configure SMTP from environment if not already configured
        if let password = Environment.get("SMTP_PASSWORD") {
            let config = SmtpServerConfiguration(
                hostname: Environment.get("SMTP_HOST") ?? "smtp.purelymail.com",
                port: Int(Environment.get("SMTP_PORT") ?? "587") ?? 587,
                username: Environment.get("SMTP_USERNAME") ?? "done@fddl.dev",
                password: password,
                secure: .startTls
            )
            app.smtp.configuration = config
        }
    }
    
    func sendInvite(to email: String, code: String, boardTitle: String?, inviterName: String) async throws {
        let subject = boardTitle != nil ? "\(inviterName) invited you to board '\(boardTitle!)' on Done." : "\(inviterName) invited you to join Done."
        
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let registrationLink = "\(baseURL)/register?code=\(code)"
        let body = """
        Hello!
        
        \(inviterName) has invited you to join \(boardTitle ?? "their team") on Done.
        
        Your invite code is: \(code)
        
        You can register and join by clicking the link below:
        \(registrationLink)
        
        See you there!
        """
        
        app.logger.info("Sending invite to \(email) via SMTP")
        
        // If password is missing, we fall back to logging (mock behavior)
        if Environment.get("SMTP_PASSWORD") == nil {
            app.logger.info("MOCK EMAIL (SMTP_PASSWORD missing): Body: \(body)")
            return
        }
        
        let mail = Email(
            from: EmailAddress(address: Environment.get("SMTP_FROM") ?? "done@fddl.dev", name: "Done."),
            to: [EmailAddress(address: email)],
            subject: subject,
            body: body
        )
        
        // Use the event loop to send the email and wait for completion
        let result = try await app.smtp.send(mail).get()
        
        switch result {
        case .success:
            app.logger.info("Email sent successfully to \(email)")
        case .failure(let error):
            app.logger.error("Failed to send email to \(email): \(error.localizedDescription)")
            throw error
        }
    }

    func sendContactForm(name: String, email: String, message: String) async throws {
        let subject = "New Contact Form Submission from \(name)"
        let body = """
        Name: \(name)
        Email: \(email)
        
        Message:
        \(message)
        """
        
        let destination = Environment.get("CONTACT_EMAIL") ?? "done@fddl.dev"
        
        app.logger.info("Sending contact form submission from \(email) to \(destination)")
        
        if Environment.get("SMTP_PASSWORD") == nil {
            app.logger.info("MOCK CONTACT EMAIL (SMTP_PASSWORD missing): Body: \(body)")
            return
        }
        
        let mail = Email(
            from: EmailAddress(address: Environment.get("SMTP_FROM") ?? "done@fddl.dev", name: "Done. Contact"),
            to: [EmailAddress(address: destination)],
            subject: subject,
            body: body,
            replyTo: EmailAddress(address: email, name: name)
        )
        
        let result = try await app.smtp.send(mail).get()
        
        switch result {
        case .success:
            app.logger.info("Contact email sent successfully")
        case .failure(let error):
            app.logger.error("Failed to send contact email: \(error.localizedDescription)")
            throw error
        }
    }
}

extension Application {
    var emailService: EmailService {
        .init(app: self)
    }
}
