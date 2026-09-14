"""
ComfyUI-PromptLoop
Batch-Verarbeitung von Prompts aus Textdateien
"""

import os
import folder_paths
import nodes


class PromptLoopFromFile:
    """
    Liest eine Textdatei und gibt jeden Prompt einzeln aus.
    Perfekt für Batch-Generierung: Ein Queue-Auftrag → Viele Bilder
    """

    @classmethod
    def INPUT_TYPES(cls):
        input_dir = folder_paths.get_input_directory()
        files = [f for f in os.listdir(input_dir) if f.endswith(".txt")]

        return {
            "required": {
                "file": (sorted(files), {"default": "prompts.txt"}),
            },
            "optional": {
                "start_index": ("INT", {"default": 0, "min": 0, "max": 10000, "step": 1}),
                "max_prompts": ("INT", {"default": 0, "min": 0, "max": 10000, "step": 1}),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("prompt",)
    OUTPUT_IS_LIST = (True,)
    FUNCTION = "execute"
    CATEGORY = "promptloop"

    def execute(self, file, start_index=0, max_prompts=0):
        """
        Liest die Textdatei und gibt alle Prompts als Liste zurück.
        ComfyUI wird automatisch für jeden Eintrag die nachfolgenden Nodes ausführen.
        """
        input_dir = folder_paths.get_input_directory()
        file_path = os.path.join(input_dir, file)

        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Datei nicht gefunden: {file_path}")

        # Datei lesen
        with open(file_path, "r", encoding="utf-8") as f:
            prompts = [line.strip() for line in f if line.strip()]

        # Slicing mit start_index und optional max_prompts
        end_index = None
        if max_prompts > 0:
            end_index = start_index + max_prompts

        prompts = prompts[start_index:end_index]

        if not prompts:
            raise ValueError(
                "Keine Prompts in der Datei gefunden (eventuell start_index zu hoch?)!"
            )

        print(
            f"[PromptLoop] Geladen: {len(prompts)} Prompts aus {file} "
            f"(Start: {start_index}, Max: {max_prompts if max_prompts > 0 else 'alle'})"
        )

        return (prompts,)


class PromptLoopFromText:
    """
    Nimmt einen mehrzeiligen Text und gibt jeden Prompt einzeln aus.
    Alternative zu File-Input für schnelles Testen.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "text": (
                    "STRING",
                    {
                        "multiline": True,
                        "default": "prompt 1\nprompt 2\nprompt 3",
                    },
                ),
            },
            "optional": {
                "start_index": ("INT", {"default": 0, "min": 0, "max": 10000, "step": 1}),
                "max_prompts": ("INT", {"default": 0, "min": 0, "max": 10000, "step": 1}),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("prompt",)
    OUTPUT_IS_LIST = (True,)
    FUNCTION = "execute"
    CATEGORY = "promptloop"

    def execute(self, text, start_index=0, max_prompts=0):
        """
        Teilt den Text in einzelne Zeilen und gibt sie als Liste zurück.
        """
        prompts = [line.strip() for line in text.split("\n") if line.strip()]

        # Slicing mit start_index und optional max_prompts
        end_index = None
        if max_prompts > 0:
            end_index = start_index + max_prompts

        prompts = prompts[start_index:end_index]

        if not prompts:
            raise ValueError("Keine Prompts im Text gefunden!")

        print(
            f"[PromptLoop] Verarbeite: {len(prompts)} Prompts "
            f"(Start: {start_index}, Max: {max_prompts if max_prompts > 0 else 'alle'})"
        )

        return (prompts,)


class PromptLoopInfo:
    """
    Zeigt Information über die aktuelle Batch-Verarbeitung.
    Nützlich für Debugging und Dateinamen.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt": ("STRING", {"forceInput": True}),
            }
        }

    RETURN_TYPES = (
        "STRING",
        "INT",
        "INT",
    )
    RETURN_NAMES = (
        "prompt",
        "current_index",
        "total_count",
    )
    FUNCTION = "execute"
    CATEGORY = "promptloop"

    def execute(self, prompt):
        """
        Gibt den Prompt zusammen mit Index-Informationen zurück.
        (Platzhalter-Implementierung – kann später erweitert werden.)
        """
        return (prompt, 0, 1)


class PromptLoopSaveImage:
    """
    Speichert Bilder mit expliziten Prompt-Metadaten.
    Kompatibel mit A1111/Civitai durch 'parameters' Feld.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images": ("IMAGE",),
                "prompt": (
                    "STRING",
                    {
                        "forceInput": True,
                        "multiline": True,
                    },
                ),
                "filename_prefix": ("STRING", {"default": "PromptLoop"}),
            },
            "optional": {
                "negative_prompt": (
                    "STRING",
                    {
                        "multiline": True,
                        "default": "",
                    },
                ),
            },
            "hidden": {
                "prompt_id": "PROMPT", 
                "extra_pnginfo": "EXTRA_PNGINFO"
            },
        }

    OUTPUT_NODE = True
    RETURN_TYPES = ()
    FUNCTION = "save_images"
    CATEGORY = "promptloop"

    def save_images(
        self,
        images,
        prompt,
        filename_prefix="PromptLoop",
        negative_prompt="",
        prompt_id=None,
        extra_pnginfo=None,
    ):
        """
        Speichert Bilder mit Prompt in Metadaten (A1111/Civitai kompatibel)
        """
        # Extra PNG Info vorbereiten
        if extra_pnginfo is None:
            extra_pnginfo = {}
        
        # Workflow-Daten aus dem System übernehmen falls vorhanden
        metadata = extra_pnginfo.copy()
        
        # Prompt explizit in 'parameters' schreiben (A1111/Civitai Standard)
        params_text = prompt.strip()
        
        if negative_prompt and negative_prompt.strip():
            params_text += f"\nNegative prompt: {negative_prompt.strip()}"
        
        # Metadaten setzen
        metadata["parameters"] = params_text
        
        # Debug-Ausgabe
        print(f"[PromptLoop] Speichere Bild mit Metadaten:")
        print(f"  Prompt: {prompt[:80]}...")
        if negative_prompt:
            print(f"  Negative: {negative_prompt[:80]}...")
        
        # Standard SaveImage nutzen
        saver = nodes.SaveImage()
        result = saver.save_images(
            images=images,
            filename_prefix=filename_prefix,
            prompt=prompt_id,
            extra_pnginfo=metadata,
        )
        
        return result


# Node-Registrierung
NODE_CLASS_MAPPINGS = {
    "PromptLoopFromFile": PromptLoopFromFile,
    "PromptLoopFromText": PromptLoopFromText,
    "PromptLoopInfo": PromptLoopInfo,
    "PromptLoopSaveImage": PromptLoopSaveImage,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "PromptLoopFromFile": "🔄 Prompt Loop (File)",
    "PromptLoopFromText": "🔄 Prompt Loop (Text)",
    "PromptLoopInfo": "ℹ️ Prompt Loop Info",
    "PromptLoopSaveImage": "💾 Prompt Loop Save Image",
}
