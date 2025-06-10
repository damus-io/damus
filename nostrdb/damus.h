//
//  damus.h
//  damus
//
//  Created by William Casarin on 2022-10-17.
//

#ifndef damus_h
#define damus_h

#include <stdio.h>
#include "block.h"

typedef unsigned char u8;

int damus_parse_content(struct note_blocks *blocks, const char *content);

#endif /* damus_h */
