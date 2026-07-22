package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	signature           = "ASMX"
	version             = uint32(1)
	headerSize          = uint32(28)
	defaultEntryOffset  = uint32(0)
	userProgramSlotSize = uint32(0x1000)
)

var listingLine = regexp.MustCompile(`^\s*\d+\s+([0-9A-Fa-f]{8})\s+(.+)$`)
var bracketedHex = regexp.MustCompile(`\[([0-9A-Fa-f]{8})\]`)

type Reloc struct {
	Offset uint32
	Value  uint32
}

func main() {
	if len(os.Args) != 2 && len(os.Args) != 4 {
		fail("usage: go run relo.go Prog1  OR  go run relo.go Prog1.bin Prog1.lst Prog1.exe")
	}

	var binPath string
	var lstPath string
	var exePath string
	var relPath string
	if len(os.Args) == 2 {
		base := os.Args[1]
		binPath = base + ".bin"
		lstPath = base + ".lst"
		exePath = base + ".exe"
		relPath = base + ".rel"
	} else {
		binPath = os.Args[1]
		lstPath = os.Args[2]
		exePath = os.Args[3]
		relPath = strings.TrimSuffix(exePath, filepath.Ext(exePath)) + ".rel"
	}

	image, err := os.ReadFile(binPath)
	if err != nil {
		fail("read %s: %v", binPath, err)
	}

	relocs, err := readRelocs(lstPath)
	if err != nil {
		fail("read relocs from %s: %v", lstPath, err)
	}

	out := make([]byte, 0, int(headerSize)+len(image)+(len(relocs)*4))
	header := make([]byte, headerSize)
	copy(header[0:4], []byte(signature))
	binary.LittleEndian.PutUint32(header[4:8], version)
	binary.LittleEndian.PutUint32(header[8:12], defaultEntryOffset)
	binary.LittleEndian.PutUint32(header[12:16], headerSize)
	binary.LittleEndian.PutUint32(header[16:20], uint32(len(image)))
	binary.LittleEndian.PutUint32(header[20:24], headerSize+uint32(len(image)))
	binary.LittleEndian.PutUint32(header[24:28], uint32(len(relocs)))

	out = append(out, header...)
	out = append(out, image...)
	for _, reloc := range relocs {
		buf := make([]byte, 4)
		binary.LittleEndian.PutUint32(buf, reloc.Offset)
		out = append(out, buf...)
	}

	if err := os.WriteFile(exePath, out, 0644); err != nil {
		fail("write %s: %v", exePath, err)
	}
	if err := writeReport(relPath, binPath, lstPath, exePath, len(image), relocs); err != nil {
		fail("write %s: %v", relPath, err)
	}

	fmt.Printf("wrote %s\n", filepath.Clean(exePath))
	fmt.Printf("wrote %s\n", filepath.Clean(relPath))
	fmt.Printf("image bytes: %d\n", len(image))
	fmt.Printf("relocations: %d\n", len(relocs))
}

func readRelocs(path string) ([]Reloc, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	seen := map[uint32]bool{}
	relocs := []Reloc{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		match := listingLine.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		lineOffset, err := parseHex32(match[1])
		if err != nil {
			return nil, err
		}
		fields := strings.Fields(match[2])
		if len(fields) == 0 {
			continue
		}
		bytesText := fields[0]
		sourceText := strings.TrimSpace(strings.TrimPrefix(match[2], bytesText))
		matches := bracketedHex.FindAllStringSubmatchIndex(bytesText, -1)
		for _, loc := range matches {
			valueText := bytesText[loc[2]:loc[3]]
			value, err := parseLittleEndianDword(valueText)
			if err != nil {
				return nil, err
			}
			if value >= userProgramSlotSize {
				continue
			}
			fieldOffset := lineOffset + uint32(hexByteLen(bytesText[:loc[0]]))
			if seen[fieldOffset] {
				continue
			}
			seen[fieldOffset] = true
			relocs = append(relocs, Reloc{
				Offset: fieldOffset,
				Value:  value,
			})
		}
		if strings.Contains(sourceText, "KC_BLOCK") {
			addKnownMemoryReloc(bytesText, lineOffset, seen, &relocs)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return relocs, nil
}

func addKnownMemoryReloc(bytesText string, lineOffset uint32, seen map[uint32]bool, relocs *[]Reloc) {
	hexText := plainHex(bytesText)
	var fieldStart uint32
	switch {
	case strings.HasPrefix(hexText, "C705") && len(hexText) >= 12:
		fieldStart = 2
	case strings.HasPrefix(hexText, "A3") && len(hexText) >= 10:
		fieldStart = 1
	default:
		return
	}
	valueText := hexText[fieldStart*2 : (fieldStart*2)+8]
	value, err := parseLittleEndianDword(valueText)
	if err != nil {
		return
	}
	if value >= userProgramSlotSize {
		return
	}
	fieldOffset := lineOffset + fieldStart
	if seen[fieldOffset] {
		return
	}
	seen[fieldOffset] = true
	*relocs = append(*relocs, Reloc{
		Offset: fieldOffset,
		Value:  value,
	})
}

func writeReport(path string, binPath string, lstPath string, exePath string, imageSize int, relocs []Reloc) error {
	var report strings.Builder
	fmt.Fprintf(&report, "AsmOSx86 relo report\n")
	fmt.Fprintf(&report, "input image: %s\n", filepath.Clean(binPath))
	fmt.Fprintf(&report, "input list:  %s\n", filepath.Clean(lstPath))
	fmt.Fprintf(&report, "output exe:  %s\n", filepath.Clean(exePath))
	fmt.Fprintf(&report, "\n")
	fmt.Fprintf(&report, "signature:   %s\n", signature)
	fmt.Fprintf(&report, "version:     %08X\n", version)
	fmt.Fprintf(&report, "entry:       %08X\n", defaultEntryOffset)
	fmt.Fprintf(&report, "image off:   %08X\n", headerSize)
	fmt.Fprintf(&report, "image size:  %08X\n", imageSize)
	fmt.Fprintf(&report, "reloc off:   %08X\n", headerSize+uint32(imageSize))
	fmt.Fprintf(&report, "reloc count: %08X\n", len(relocs))
	fmt.Fprintf(&report, "\n")
	fmt.Fprintf(&report, "relocations:\n")
	for _, reloc := range relocs {
		fmt.Fprintf(&report, "  image+%08X value %08X\n", reloc.Offset, reloc.Value)
	}
	return os.WriteFile(path, []byte(report.String()), 0644)
}

func parseHex32(text string) (uint32, error) {
	value, err := strconv.ParseUint(text, 16, 32)
	return uint32(value), err
}

func parseLittleEndianDword(text string) (uint32, error) {
	if len(text) != 8 {
		return 0, fmt.Errorf("expected 8 hex chars, got %q", text)
	}
	b0, err := strconv.ParseUint(text[0:2], 16, 8)
	if err != nil {
		return 0, err
	}
	b1, err := strconv.ParseUint(text[2:4], 16, 8)
	if err != nil {
		return 0, err
	}
	b2, err := strconv.ParseUint(text[4:6], 16, 8)
	if err != nil {
		return 0, err
	}
	b3, err := strconv.ParseUint(text[6:8], 16, 8)
	if err != nil {
		return 0, err
	}
	return uint32(b0) | uint32(b1)<<8 | uint32(b2)<<16 | uint32(b3)<<24, nil
}

func hexByteLen(text string) int {
	count := 0
	for _, r := range text {
		if (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F') {
			count++
		}
	}
	return count / 2
}

func plainHex(text string) string {
	var b strings.Builder
	for _, r := range text {
		if (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F') {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
