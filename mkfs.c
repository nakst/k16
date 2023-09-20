#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

// 360 kb floppy: 2 sides; 40 tracks/sides; 9 sectors/track; 512 bytes/sector.

// Filesystem format:
// 	boot sector (1), sector usage table (3), data sectors (716)
// 	sector usage table is made of 720 WORDs, one per sector
// 		0xFFFF = unused, 0xFFFE = end of file, 0xFFFD = metadata, 0x0000 = does not exist
// 		otherwise points to next sector in file
// 	boot sectors ends with 'k16fs', sector usage table size in sectors (1 byte), 55, AA
// 	root directory starts after the metadata sectors
// 	16 directory entries per sector

typedef struct DirectoryEntry {
	uint8_t name[20];
#define ATTRIBUTE_DIRECTORY (1 << 0)
#define ATTRIBUTE_USED      (1 << 1)
	uint8_t attributes;
	uint8_t sizeHigh; // Unused for directories.
	uint16_t firstSector;
	uint16_t sizeLow; // Unused for directories.
	uint16_t unused0;
	uint16_t unused1;
	uint16_t unused2;
} DirectoryEntry;

uint8_t buffer[720 * 512];

int main(int argc, char **argv) {
	size_t filesToAddCount = (argc - 1) / 2;
	uint16_t *sectorTable = (uint16_t *) (buffer + 0x0200);
	size_t rootDirectorySectorCount = (filesToAddCount + 27) / 28;
	size_t metadataSectors = 1 + 3;
	size_t currentSector = metadataSectors;

	FILE *file;

	for (uintptr_t i = 0; i < 720; i++) {
		sectorTable[i] = i < metadataSectors ? 0xFFFD : 0xFFFF;
	}

	for (uintptr_t i = 0; i < rootDirectorySectorCount; i++, currentSector++) {
		sectorTable[currentSector] = i == rootDirectorySectorCount - 1 ? 0xFFFE : (currentSector + 1);
	}

	for (uintptr_t i = 0; i < filesToAddCount; i++) {
		DirectoryEntry *entry = (DirectoryEntry *) (buffer + 0x800 + 0x200 * (i / 16) + 32 * (i % 16));
		file = fopen(argv[i * 2 + 1], "rb");
		size_t byteCount = fread(&buffer[0x200 * currentSector], 1, sizeof(buffer) - 0x200 * currentSector, file);
		printf("%s -> %s (%d KB)\n", argv[i * 2 + 1], argv[i * 2 + 2], (int) (byteCount + 1023) / 1024);
		size_t sectorCount = (byteCount + 0x1FF) / 0x200;
		fclose(file);
		assert(strlen(argv[i * 2 + 2]) <= sizeof(entry->name));
		memcpy(&entry->name[0], argv[i * 2 + 2], strlen(argv[i * 2 + 2]));
		entry->attributes = ATTRIBUTE_USED;
		entry->firstSector = currentSector;
		entry->sizeLow = byteCount & 0xFFFF;
		entry->sizeHigh = (byteCount >> 16) & 0xFFFF;

		for (uintptr_t j = 0; j < sectorCount; j++, currentSector++) {
			sectorTable[currentSector] = j == sectorCount - 1 ? 0xFFFE : (currentSector + 1);
		}
	}

	file = fopen("bin/boot", "rb");
	fread(buffer, 1, 512, file);
	fclose(file);

	file = fopen("bin/drive.img", "wb");
	fwrite(buffer, 1, sizeof(buffer), file);
	fclose(file);

	return 0;
}
