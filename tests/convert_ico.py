from PIL import Image
import sys
import os

def convert_png_to_ico(png_path, ico_path):
    if not os.path.exists(png_path):
        print(f"Error: Source image '{png_path}' does not exist.")
        sys.exit(1)
        
    img = Image.open(png_path)
    # Define standard Windows icon resolutions
    sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    # Save as ICO format containing all size frames
    img.save(ico_path, format='ICO', sizes=sizes)
    print(f"Successfully converted '{png_path}' to '{ico_path}' with multi-resolution sizes.")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python convert_ico.py <input_png> <output_ico>")
        sys.exit(1)
    
    convert_png_to_ico(sys.argv[1], sys.argv[2])
