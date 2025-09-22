package main

import (
	"database/sql"
	"fmt"
	"log"
	"net"
	"strconv"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

const (
	DB_FILE   = "mails.db"
	SERVER_IP = "0.0.0.0:143" // Use non-privileged port
)

type IMAPServer struct {
	db *sql.DB
}

type ClientState struct {
	authenticated  bool
	selectedFolder string
	conn           net.Conn
}

func (s *IMAPServer) initDB() error {
	var err error
	s.db, err = sql.Open("sqlite3", DB_FILE)
	if err != nil {
		return err
	}

	// Create tables if they don't exist
	createTables := `
	CREATE TABLE IF NOT EXISTS mails (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		subject TEXT,
		sender TEXT,
		recipient TEXT,
		date_sent TEXT,
		raw_message TEXT,
		flags TEXT DEFAULT '',
		folder TEXT DEFAULT 'INBOX'
	);
	
	CREATE TABLE IF NOT EXISTS folders (
		name TEXT PRIMARY KEY,
		delimiter TEXT DEFAULT '/',
		attributes TEXT DEFAULT ''
	);
	
	INSERT OR IGNORE INTO folders (name, attributes) VALUES ('INBOX', '');
	INSERT OR IGNORE INTO folders (name, attributes) VALUES ('Sent', '');
	INSERT OR IGNORE INTO folders (name, attributes) VALUES ('Drafts', '');
	INSERT OR IGNORE INTO folders (name, attributes) VALUES ('Trash', '');
	`

	_, err = s.db.Exec(createTables)
	if err != nil {
		return err
	}

	// Insert sample emails if none exist
	var count int
	err = s.db.QueryRow("SELECT COUNT(*) FROM mails").Scan(&count)
	if err == nil && count == 0 {
		s.insertSampleEmails()
	}

	return nil
}

func (s *IMAPServer) insertSampleEmails() {
	sampleEmails := []struct {
		subject, sender, recipient, rawMessage string
	}{
		{
			"Welcome to SQLite IMAP",
			"admin@example.com",
			"user@example.com",
			"From: admin@example.com\r\nTo: user@example.com\r\nSubject: Welcome to SQLite IMAP\r\nDate: " + time.Now().Format(time.RFC1123Z) + "\r\n\r\nWelcome to your SQLite IMAP server!\r\n\r\nThis is a test message.\r\n",
		},
		{
			"Test Message 2",
			"test@example.com",
			"user@example.com",
			"From: test@example.com\r\nTo: user@example.com\r\nSubject: Test Message 2\r\nDate: " + time.Now().Add(-24*time.Hour).Format(time.RFC1123Z) + "\r\n\r\nThis is another test message with some content.\r\n\r\nBest regards,\r\nTest User\r\n",
		},
	}

	for _, email := range sampleEmails {
		s.db.Exec("INSERT INTO mails (subject, sender, recipient, date_sent, raw_message, folder) VALUES (?, ?, ?, ?, ?, 'INBOX')",
			email.subject, email.sender, email.recipient, time.Now().Format(time.RFC1123Z), email.rawMessage)
	}
}

func (s *IMAPServer) handleConnection(conn net.Conn) {
	defer conn.Close()

	state := &ClientState{
		authenticated: false,
		conn:          conn,
	}

	// Send greeting
	s.sendResponse(conn, "* OK [CAPABILITY IMAP4rev1 UIDPLUS IDLE] SQLite IMAP server ready")

	buf := make([]byte, 4096)
	for {
		conn.SetReadDeadline(time.Now().Add(30 * time.Minute))
		n, err := conn.Read(buf)
		if err != nil {
			return
		}

		line := strings.TrimSpace(string(buf[:n]))
		if line == "" {
			continue
		}

		fmt.Printf("Client: %s\n", line)
		parts := strings.Fields(line)
		if len(parts) < 2 {
			s.sendResponse(conn, "* BAD Invalid command format")
			continue
		}

		tag := parts[0]
		cmd := strings.ToUpper(parts[1])

		if cmd == "UID" && len(parts) > 2 {
			subCmd := strings.ToUpper(parts[2])
			switch subCmd {
			case "FETCH":
				s.handleUIDFetch(conn, tag, parts, state)
			case "SEARCH":
				s.handleUIDSearch(conn, tag, parts, state)
			case "STORE":
				s.handleUIDStore(conn, tag, parts, state)
			default:
				s.sendResponse(conn, fmt.Sprintf("%s BAD Unknown UID subcommand: %s", tag, subCmd))
			}
			continue
		}
		if cmd == "IDLE" {
			s.handleIdle(conn, tag, state)
			continue
		}

		switch cmd {
		case "CAPABILITY":
			s.handleCapability(conn, tag)
		case "LOGIN":
			s.handleLogin(conn, tag, parts, state)
		case "LIST":
			s.handleList(conn, tag, parts, state)
		case "SELECT", "EXAMINE":
			s.handleSelect(conn, tag, parts, state)
		case "FETCH":
			s.handleFetch(conn, tag, parts, state)
		case "SEARCH":
			s.handleSearch(conn, tag, parts, state)
		case "STATUS":
			s.handleStatus(conn, tag, parts, state)
		case "NOOP":
			s.sendResponse(conn, fmt.Sprintf("%s OK NOOP completed", tag))
		case "LOGOUT":
			s.handleLogout(conn, tag)
			return
		default:
			s.sendResponse(conn, fmt.Sprintf("%s BAD Unknown command: %s", tag, cmd))
		}
	}
}

func (s *IMAPServer) sendResponse(conn net.Conn, response string) {
	fmt.Printf("Server: %s\n", response)
	conn.Write([]byte(response + "\r\n"))
}

func (s *IMAPServer) handleCapability(conn net.Conn, tag string) {
	s.sendResponse(conn, "* CAPABILITY IMAP4rev1 LOGIN IDLE")
	s.sendResponse(conn, fmt.Sprintf("%s OK CAPABILITY completed", tag))
}

func (s *IMAPServer) handleLogin(conn net.Conn, tag string, parts []string, state *ClientState) {
	if len(parts) < 4 {
		s.sendResponse(conn, fmt.Sprintf("%s BAD LOGIN requires username and password", tag))
		return
	}
	// Accept any username/password for demo purposes
	state.authenticated = true
	s.sendResponse(conn, fmt.Sprintf("%s OK LOGIN completed", tag))
}

func (s *IMAPServer) handleList(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	// List folders
	folders := []struct{ name, attrs string }{
		{"INBOX", ""},
		{"Sent", ""},
		{"Drafts", "\\Drafts"},
		{"Trash", "\\Trash"},
	}

	for _, folder := range folders {
		attrs := folder.attrs
		if attrs == "" {
			attrs = "\\Unmarked"
		}
		s.sendResponse(conn, fmt.Sprintf("* LIST (%s) \"/\" \"%s\"", attrs, folder.name))
	}
	s.sendResponse(conn, fmt.Sprintf("%s OK LIST completed", tag))
}

func (s *IMAPServer) handleSelect(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	if len(parts) < 3 {
		s.sendResponse(conn, fmt.Sprintf("%s BAD SELECT requires folder name", tag))
		return
	}

	folder := strings.Trim(parts[2], "\"")
	state.selectedFolder = folder

	// Get message count
	var count int
	err := s.db.QueryRow("SELECT COUNT(*) FROM mails WHERE folder = ?", folder).Scan(&count)
	if err != nil {
		count = 0
	}

	// Get recent count (messages without \Seen flag)
	var recent int
	err = s.db.QueryRow("SELECT COUNT(*) FROM mails WHERE folder = ? AND flags NOT LIKE '%\\Seen%'", folder).Scan(&recent)
	if err != nil {
		recent = 0
	}

	// Send required untagged responses
	s.sendResponse(conn, fmt.Sprintf("* %d EXISTS", count))
	s.sendResponse(conn, fmt.Sprintf("* %d RECENT", recent))
	s.sendResponse(conn, "* OK [UIDVALIDITY 1] UID validity status")
	s.sendResponse(conn, fmt.Sprintf("* OK [UIDNEXT %d] Predicted next UID", count+1))
	s.sendResponse(conn, "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)")
	s.sendResponse(conn, "* OK [PERMANENTFLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft \\*)] Flags permitted")

	cmd := strings.ToUpper(parts[1])
	if cmd == "SELECT" {
		s.sendResponse(conn, fmt.Sprintf("%s OK [READ-WRITE] SELECT completed", tag))
	} else {
		s.sendResponse(conn, fmt.Sprintf("%s OK [READ-ONLY] EXAMINE completed", tag))
	}
}

func (s *IMAPServer) handleFetch(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	if state.selectedFolder == "" {
		s.sendResponse(conn, fmt.Sprintf("%s NO No folder selected", tag))
		return
	}

	if len(parts) < 4 {
		s.sendResponse(conn, fmt.Sprintf("%s BAD FETCH requires sequence and items", tag))
		return
	}

	sequence := parts[2]
	items := strings.Join(parts[3:], " ")
	items = strings.Trim(items, "()")

	// Parse sequence (simplified - handle 1:* and individual numbers)
	var rows *sql.Rows
	var err error

	if sequence == "1:*" {
		rows, err = s.db.Query("SELECT id, raw_message, flags FROM mails WHERE folder = ? ORDER BY id ASC", state.selectedFolder)
	} else {
		// Handle individual message numbers
		msgNum, parseErr := strconv.Atoi(sequence)
		if parseErr != nil {
			s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid sequence number", tag))
			return
		}
		rows, err = s.db.Query("SELECT id, raw_message, flags FROM mails WHERE folder = ? ORDER BY id ASC LIMIT 1 OFFSET ?", state.selectedFolder, msgNum-1)
	}

	if err != nil {
		s.sendResponse(conn, fmt.Sprintf("%s NO Database error", tag))
		return
	}
	defer rows.Close()

	seqNum := 1
	for rows.Next() {
		var id int
		var rawMsg, flags string
		rows.Scan(&id, &rawMsg, &flags)

		// Ensure proper CRLF line endings
		if !strings.Contains(rawMsg, "\r\n") {
			rawMsg = strings.ReplaceAll(rawMsg, "\n", "\r\n")
		}

		// Handle different FETCH items
		itemsUpper := strings.ToUpper(items)
		if strings.Contains(itemsUpper, "BODY[]") || strings.Contains(itemsUpper, "RFC822") {
			// Return full message
			s.sendResponse(conn, fmt.Sprintf("* %d FETCH (BODY[] {%d}", seqNum, len(rawMsg)))
			conn.Write([]byte(rawMsg + "\r\n"))
			s.sendResponse(conn, ")")
		} else if strings.Contains(itemsUpper, "FLAGS") {
			// Return flags
			if flags == "" {
				flags = "()"
			} else {
				flags = fmt.Sprintf("(%s)", flags)
			}
			s.sendResponse(conn, fmt.Sprintf("* %d FETCH (FLAGS %s)", seqNum, flags))
		} else {
			// Default response
			s.sendResponse(conn, fmt.Sprintf("* %d FETCH (FLAGS ())", seqNum))
		}
		seqNum++
	}

	s.sendResponse(conn, fmt.Sprintf("%s OK FETCH completed", tag))
}

func (s *IMAPServer) handleUIDFetch(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	if state.selectedFolder == "" {
		s.sendResponse(conn, fmt.Sprintf("%s NO No folder selected", tag))
		return
	}

	if len(parts) < 5 {
		s.sendResponse(conn, fmt.Sprintf("%s BAD UID FETCH requires sequence and items", tag))
		return
	}

	sequence := parts[3]
	items := strings.Join(parts[4:], " ")
	items = strings.Trim(items, "()")

	// Parse UID sequence
	var rows *sql.Rows
	var err error

	if sequence == "1:*" {
		rows, err = s.db.Query("SELECT id, raw_message, flags, ROW_NUMBER() OVER (ORDER BY id ASC) as seq FROM mails WHERE folder = ? ORDER BY id ASC", state.selectedFolder)
	} else if strings.Contains(sequence, ":") {
		// Handle UID range, e.g., 1:2
		parts := strings.Split(sequence, ":")
		if len(parts) == 2 {
			start, err1 := strconv.Atoi(parts[0])
			end, err2 := strconv.Atoi(parts[1])
			if err1 != nil || err2 != nil || start > end {
				s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid UID range", tag))
				return
			}
			rows, err = s.db.Query("SELECT id, raw_message, flags, ROW_NUMBER() OVER (ORDER BY id ASC) as seq FROM mails WHERE folder = ? AND id >= ? AND id <= ? ORDER BY id ASC", state.selectedFolder, start, end)
		} else {
			s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid UID range format", tag))
			return
		}
	} else {
		// Handle individual UID numbers
		uid, parseErr := strconv.Atoi(sequence)
		if parseErr != nil {
			s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid UID", tag))
			return
		}
		rows, err = s.db.Query("SELECT id, raw_message, flags, ROW_NUMBER() OVER (ORDER BY id ASC) as seq FROM mails WHERE folder = ? AND id = ?", state.selectedFolder, uid)
	}

	if err != nil {
		s.sendResponse(conn, fmt.Sprintf("%s NO Database error", tag))
		return
	}
	defer rows.Close()

	for rows.Next() {
		var id, seqNum int
		var rawMsg, flags string
		rows.Scan(&id, &rawMsg, &flags, &seqNum)

		// Ensure proper CRLF
		if !strings.Contains(rawMsg, "\r\n") {
			rawMsg = strings.ReplaceAll(rawMsg, "\n", "\r\n")
		}

		itemsUpper := strings.ToUpper(items)
		var responseParts []string

		if strings.Contains(itemsUpper, "UID") || true {
			responseParts = append(responseParts, fmt.Sprintf("UID %d", id))
		}

		if strings.Contains(itemsUpper, "FLAGS") {
			flagsStr := "()"
			if flags != "" {
				flagsStr = fmt.Sprintf("(%s)", flags)
			}
			responseParts = append(responseParts, fmt.Sprintf("FLAGS %s", flagsStr))
		}

		if strings.Contains(itemsUpper, "RFC822.SIZE") {
			responseParts = append(responseParts, fmt.Sprintf("RFC822.SIZE %d", len(rawMsg)))
		}

		if strings.Contains(itemsUpper, "BODY.PEEK[HEADER.FIELDS") {
			// Extract requested header fields
			start := strings.Index(itemsUpper, "BODY.PEEK[HEADER.FIELDS")
			end := strings.Index(itemsUpper[start:], "]")
			headers := []string{"FROM", "TO", "CC", "BCC", "SUBJECT", "DATE", "MESSAGE-ID", "PRIORITY", "X-PRIORITY", "REFERENCES", "NEWSGROUPS", "IN-REPLY-TO", "CONTENT-TYPE", "REPLY-TO"}
			if start != -1 && end != -1 {
				fieldsStr := items[start+len("BODY.PEEK[HEADER.FIELDS (") : start+end]
				fields := strings.FieldsFunc(fieldsStr, func(r rune) bool { return r == ' ' || r == ',' })
				if len(fields) > 0 {
					headers = []string{}
					for _, f := range fields {
						headers = append(headers, strings.ToUpper(strings.TrimSpace(f)))
					}
				}
			}
			// Parse rawMsg headers
			headersMap := map[string]string{}
			lines := strings.Split(rawMsg, "\r\n")
			for _, line := range lines {
				for _, h := range headers {
					if strings.HasPrefix(strings.ToUpper(line), h+":") {
						headersMap[h] = line
					}
				}
			}
			var headerLines []string
			for _, h := range headers {
				if val, ok := headersMap[h]; ok {
					headerLines = append(headerLines, val)
				}
			}
			headersStr := strings.Join(headerLines, "\r\n") + "\r\n\r\n"
			responseParts = append(responseParts, fmt.Sprintf("BODY[HEADER] {%d}", len(headersStr)))
			s.sendResponse(conn, fmt.Sprintf("* %d FETCH (%s)", seqNum, strings.Join(responseParts, " ")))
			conn.Write([]byte(headersStr))
			s.sendResponse(conn, ")")
			continue
		}

		if strings.Contains(itemsUpper, "BODY[]") || strings.Contains(itemsUpper, "RFC822") {
			responseParts = append(responseParts, fmt.Sprintf("BODY[] {%d}", len(rawMsg)))
			s.sendResponse(conn, fmt.Sprintf("* %d FETCH (%s)", seqNum, strings.Join(responseParts, " ")))
			conn.Write([]byte(rawMsg + "\r\n"))
			s.sendResponse(conn, ")")
		} else {
			s.sendResponse(conn, fmt.Sprintf("* %d FETCH (%s)", seqNum, strings.Join(responseParts, " ")))
		}
	}

	s.sendResponse(conn, fmt.Sprintf("%s OK UID FETCH completed", tag))
}

func (s *IMAPServer) handleUIDSearch(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	if state.selectedFolder == "" {
		s.sendResponse(conn, fmt.Sprintf("%s NO No folder selected", tag))
		return
	}

	// Simple UID search - return all UIDs
	rows, err := s.db.Query("SELECT id FROM mails WHERE folder = ? ORDER BY id ASC", state.selectedFolder)
	if err != nil {
		s.sendResponse(conn, fmt.Sprintf("%s NO Search failed", tag))
		return
	}
	defer rows.Close()

	var results []string
	for rows.Next() {
		var uid int
		rows.Scan(&uid)
		results = append(results, strconv.Itoa(uid))
	}

	s.sendResponse(conn, fmt.Sprintf("* SEARCH %s", strings.Join(results, " ")))
	s.sendResponse(conn, fmt.Sprintf("%s OK UID SEARCH completed", tag))
}

func (s *IMAPServer) handleSearch(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	if state.selectedFolder == "" {
		s.sendResponse(conn, fmt.Sprintf("%s NO No folder selected", tag))
		return
	}

	// Simple search - return all message numbers
	rows, err := s.db.Query("SELECT ROW_NUMBER() OVER (ORDER BY id ASC) as seq FROM mails WHERE folder = ?", state.selectedFolder)
	if err != nil {
		s.sendResponse(conn, fmt.Sprintf("%s NO Search failed", tag))
		return
	}
	defer rows.Close()

	var results []string
	for rows.Next() {
		var seq int
		rows.Scan(&seq)
		results = append(results, strconv.Itoa(seq))
	}

	s.sendResponse(conn, fmt.Sprintf("* SEARCH %s", strings.Join(results, " ")))
	s.sendResponse(conn, fmt.Sprintf("%s OK SEARCH completed", tag))
}

func (s *IMAPServer) handleStatus(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	if len(parts) < 4 {
		s.sendResponse(conn, fmt.Sprintf("%s BAD STATUS requires folder and items", tag))
		return
	}

	folder := strings.Trim(parts[2], "\"")

	var count int
	s.db.QueryRow("SELECT COUNT(*) FROM mails WHERE folder = ?", folder).Scan(&count)

	s.sendResponse(conn, fmt.Sprintf("* STATUS \"%s\" (MESSAGES %d RECENT 0 UIDNEXT %d UIDVALIDITY 1 UNSEEN 0)", folder, count, count+1))
	s.sendResponse(conn, fmt.Sprintf("%s OK STATUS completed", tag))
}

func (s *IMAPServer) handleLogout(conn net.Conn, tag string) {
	s.sendResponse(conn, "* BYE SQLite IMAP server logging out")
	s.sendResponse(conn, fmt.Sprintf("%s OK LOGOUT completed", tag))
}

func (s *IMAPServer) handleIdle(conn net.Conn, tag string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}

	// Simple IDLE implementation - just respond that we're ready and wait for DONE
	s.sendResponse(conn, "+ idling")

	// In a real implementation, we would wait for "DONE" command
	// For simplicity, we'll just immediately return OK
	s.sendResponse(conn, fmt.Sprintf("%s OK IDLE completed", tag))
}

func (s *IMAPServer) handleUIDStore(conn net.Conn, tag string, parts []string, state *ClientState) {
	if !state.authenticated {
		s.sendResponse(conn, fmt.Sprintf("%s NO Please authenticate first", tag))
		return
	}
	if state.selectedFolder == "" {
		s.sendResponse(conn, fmt.Sprintf("%s NO No folder selected", tag))
		return
	}
	if len(parts) < 6 {
		s.sendResponse(conn, fmt.Sprintf("%s BAD UID STORE requires sequence, operation, and flags", tag))
		return
	}
	sequence := parts[3]
	flagsStr := strings.Join(parts[5:], " ")
	flagsStr = strings.Trim(flagsStr, "()")

	// Only support adding \Seen for now
	if !strings.Contains(flagsStr, "\\Seen") {
		s.sendResponse(conn, fmt.Sprintf("%s BAD Only \\Seen flag supported", tag))
		return
	}

	var err error
	if sequence == "1:*" {
		_, err = s.db.Exec("UPDATE mails SET flags = CASE WHEN flags LIKE '%\\Seen%' THEN flags ELSE flags || ' \\Seen' END WHERE folder = ?", state.selectedFolder)
	} else if strings.Contains(sequence, ":") {
		parts := strings.Split(sequence, ":")
		if len(parts) == 2 {
			start, err1 := strconv.Atoi(parts[0])
			end, err2 := strconv.Atoi(parts[1])
			if err1 != nil || err2 != nil || start > end {
				s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid UID range", tag))
				return
			}
			_, err = s.db.Exec("UPDATE mails SET flags = CASE WHEN flags LIKE '%\\Seen%' THEN flags ELSE flags || ' \\Seen' END WHERE folder = ? AND id >= ? AND id <= ?", state.selectedFolder, start, end)
		} else {
			s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid UID range format", tag))
			return
		}
	} else {
		uid, parseErr := strconv.Atoi(sequence)
		if parseErr != nil {
			s.sendResponse(conn, fmt.Sprintf("%s BAD Invalid UID", tag))
			return
		}
		_, err = s.db.Exec("UPDATE mails SET flags = CASE WHEN flags LIKE '%\\Seen%' THEN flags ELSE flags || ' \\Seen' END WHERE folder = ? AND id = ?", state.selectedFolder, uid)
	}

	if err != nil {
		s.sendResponse(conn, fmt.Sprintf("%s NO Database error", tag))
		return
	}

	s.sendResponse(conn, fmt.Sprintf("%s OK STORE completed", tag))
}

func main() {
	server := &IMAPServer{}

	// Initialize database
	if err := server.initDB(); err != nil {
		log.Fatal("Failed to initialize database:", err)
	}
	defer server.db.Close()

	// Start listening
	ln, err := net.Listen("tcp", SERVER_IP)
	if err != nil {
		log.Fatal(err)
	}
	defer ln.Close()

	log.Printf("SQLite IMAP server running on %s", SERVER_IP)
	log.Println("Configure your email client with:")
	log.Println("  Server: localhost")
	log.Println("  Port: 143")
	log.Println("  Security: None")
	log.Println("  Username: any")
	log.Println("  Password: any")

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Println("Accept error:", err)
			continue
		}
		go server.handleConnection(conn)
	}
}
