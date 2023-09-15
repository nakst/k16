#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#define BITMAP_FONT_SIGNATURE (0xF67DD870) // (Random number.)

typedef struct OutFont {
	uint16_t yAscent;
	uint16_t yDescent;

	struct {
		uint16_t bitsOffset;
		int8_t xOrigin;
		int8_t yOrigin;
		int8_t xAdvance;
		uint8_t bitsWidth;
		uint8_t bitsHeight;
		uint8_t padding;
	} glyphs[0x80];
} OutFont;

typedef struct BitmapFontHeader {
	uint32_t signature;
	uint16_t glyphCount;
	uint8_t headerBytes, glyphBytes;
	uint16_t yAscent, yDescent;
	uint16_t xEmWidth;
	uint16_t _unused0;
	// Followed by glyphCount copies of BitmapFontGlyph, sorted by codepoint.
} BitmapFontHeader;

typedef struct BitmapFontKerningEntry {
	uint32_t rightCodepoint;
	int16_t xOffset;
	uint16_t _unused0;
} BitmapFontKerningEntry;

typedef struct BitmapFontGlyph {
	uint32_t bitsOffset; // Stored one row after another; each row is padded to a multiple of 8 bits.
	uint32_t codepoint;
	int16_t xOrigin, yOrigin, xAdvance;
	uint16_t kerningEntryCount; // Stored after the bits. Not necessarily aligned!
	uint16_t bitsWidth, bitsHeight;
} BitmapFontGlyph;

uint8_t in[65536];
uint8_t out[65536];

int main(int argc, char **argv) {
	fread(in, 1, sizeof(in), fopen(argv[1], "rb"));
	BitmapFontHeader *header = (BitmapFontHeader *) &in[0];
	assert(header->signature == BITMAP_FONT_SIGNATURE);

	OutFont *outHeader = (OutFont *) &out[0];
	outHeader->yAscent = header->yAscent;
	outHeader->yDescent = header->yDescent;
	size_t outBytes = sizeof(OutFont);

	for (uintptr_t i = 0; i < header->glyphCount; i++) {
		BitmapFontGlyph *glyph = (BitmapFontGlyph *) (header + 1) + i;

		if (glyph->codepoint < 0x80) {
			outHeader->glyphs[glyph->codepoint].bitsOffset = outBytes;
			outHeader->glyphs[glyph->codepoint].xOrigin = glyph->xOrigin;
			outHeader->glyphs[glyph->codepoint].yOrigin = glyph->yOrigin;
			outHeader->glyphs[glyph->codepoint].xAdvance = glyph->xAdvance;
			outHeader->glyphs[glyph->codepoint].bitsWidth = glyph->bitsWidth;
			outHeader->glyphs[glyph->codepoint].bitsHeight = glyph->bitsHeight;

			for (uintptr_t j = 0; j < glyph->bitsHeight * (glyph->bitsWidth + 7) / 8; j++) {
				uint8_t b = in[glyph->bitsOffset + j];
				uint8_t c = 0;

				for (uintptr_t k = 0; k < 8; k++) {
					if (b & (1 << k)) {
						c |= 1 << (7 - k);
					}
				}

				out[outBytes++] = c;
			}
		}
	}

	FILE *f = fopen(argv[2], "wb");
	fprintf(f, "%s:\n", argv[3]);

	for (int i = 0; i < outBytes; i++) {
		fprintf(f, "\tdb %d\n", out[i]);
	}

	return 0;
}
