# ComfyUI-PromptLoop

Batch processing of prompts from text files - One queue job for many images!

## Features

🔄 **Prompt Loop (File)** - Reads prompts from .txt files  
🔄 **Prompt Loop (Text)** - Processes multi-line text  
ℹ️ **Prompt Loop Info** - Shows index and counter  
💾 **Prompt Loop Save Image** - Saves images with prompt metadata

## Installation

1. Copy this folder to `ComfyUI/custom_nodes/`
2. Restart ComfyUI
3. Nodes will appear under "promptloop" category

## Usage

### Basic Workflow

1. Create a `prompts.txt` in the `input/` folder (one prompt per line)
2. Add the **Prompt Loop (File)** node
3. Connect the output to **CLIPTextEncode**
4. Use **Prompt Loop Save Image** instead of the standard Save Image node
5. One queue job → All prompts will be processed with metadata!

### Workflow Example

```
Prompt Loop (File) → prompt → CLIPTextEncode → KSampler → VAEDecode
                       ↓                                      ↓
                  Prompt Loop Save Image ←────────────────────┘
```

### Saving Images with Metadata

The **Prompt Loop Save Image** node automatically embeds your prompts into the PNG metadata, making them compatible with tools like A1111 and Civitai.

**Inputs:**
- **images**: The generated images (from VAEDecode)
- **prompt**: The positive prompt (connect from Prompt Loop node)
- **filename_prefix**: Custom filename prefix (default: "PromptLoop")
- **negative_prompt** (optional): Can be connected from another node or entered as text

## Node Options

### Prompt Loop (File)
- **file**: Select .txt file from input folder
- **start_index**: Skip the first X prompts (default: 0)
- **max_prompts**: Limit to X prompts (0 = all prompts)

### Prompt Loop (Text)
- **text**: Multi-line text input (one prompt per line)
- **start_index**: Skip the first X prompts
- **max_prompts**: Limit to X prompts

### Prompt Loop Save Image
- **filename_prefix**: Output filename prefix
- **negative_prompt**: Optional negative prompt (widget or connection)

## Example

```
input/prompts.txt:
a beautiful sunset over mountains
a futuristic city at night
a cute cat sleeping on a pillow

→ Generates 3 images with one queue job!
→ Each image contains its prompt in the metadata!
```

## Tips

- Use **start_index** and **max_prompts** to process specific ranges
- The negative prompt can be the same for all images (widget) or dynamic (connection)
- Metadata is A1111/Civitai compatible for easy sharing

---

Created by max with Claude
