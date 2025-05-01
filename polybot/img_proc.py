from pathlib import Path
from matplotlib.image import imread, imsave
import random

def rgb2gray(rgb):
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    gray = 0.2989 * r + 0.5870 * g + 0.1140 * b
    return gray


class Img:

    def __init__(self, path):
        """
        Do not change the constructor implementation
        """
        self.path = Path(path)
        self.data = rgb2gray(imread(path)).tolist()

    def save_img(self):
        """
        Do not change the below implementation
        """
        new_path = self.path.with_name(self.path.stem + '_filtered' + self.path.suffix)
        imsave(new_path, self.data, cmap='gray')
        return new_path

    def blur(self, blur_level=16):

        height = len(self.data)
        width = len(self.data[0])
        filter_sum = blur_level ** 2

        result = []
        for i in range(height - blur_level + 1):
            row_result = []
            for j in range(width - blur_level + 1):
                sub_matrix = [row[j:j + blur_level] for row in self.data[i:i + blur_level]]
                average = sum(sum(sub_row) for sub_row in sub_matrix) // filter_sum
                row_result.append(average)
            result.append(row_result)

        self.data = result

    def contour(self):
        for i, row in enumerate(self.data):
            res = []
            for j in range(1, len(row)):
                res.append(abs(row[j-1] - row[j]))

            self.data[i] = res

    def rotate(self):
        """
        Rotates the image 90 degrees clockwise
        """
        height = len(self.data)
        width = len(self.data[0])
        
        # Create a new matrix for the rotated image
        rotated_data = []
        for j in range(width):
            new_row = []
            for i in range(height - 1, -1, -1):
                new_row.append(self.data[i][j])
            rotated_data.append(new_row)
        
        self.data = rotated_data

    def salt_n_pepper(self):
        """
        Add salt and pepper noise to the image
        
        Parameters:
        salt_prob (float): Probability of salt noise (white pixels)
        pepper_prob (float): Probability of pepper noise (black pixels)
        """        
        height = len(self.data)
        width = len(self.data[0])
        
        # Apply salt (white) noise
        num_salt = int(height * width * salt_prob)
        for _ in range(num_salt):
            y = random.randint(0, height - 1)
            x = random.randint(0, width - 1)
            self.data[y][x] = 255  # White pixel
        
        # Apply pepper (black) noise
        num_pepper = int(height * width * pepper_prob)
        for _ in range(num_pepper):
            y = random.randint(0, height - 1)
            x = random.randint(0, width - 1)
            self.data[y][x] = 0  # Black pixel

    def segment(self, threshold=128):
        """
        Segment the image by thresholding (binary segmentation)
        
        Parameters:
        threshold (int): Pixel values above this will be white, below will be black
        """
        height = len(self.data)
        width = len(self.data[0])
        
        for i in range(height):
            for j in range(width):
                if self.data[i][j] > threshold:
                    self.data[i][j] = 255  # White
                else:
                    self.data[i][j] = 0  # Black

    def concat(self, other_img, direction='horizontal'):
        """
        Concatenate this image with another image
        
        Parameters:
        other_img (Img): The other image to concatenate with
        direction (str): 'horizontal' or 'vertical'
        
        Note: This method assumes that other_img is an instance of Img class
        """
        if direction not in ['horizontal', 'vertical']:
            raise ValueError("Direction must be 'horizontal' or 'vertical'")
        
        # Convert other_img to grayscale if it's not already
        other_data = other_img.data
        
        if direction == 'horizontal':
            # Check if heights are compatible
            if len(self.data) != len(other_data):
                # If heights are different, resize to the smaller height
                min_height = min(len(self.data), len(other_data))
                self.data = self.data[:min_height]
                other_data = other_data[:min_height]
            
            # Concatenate horizontally
            result = []
            for i in range(len(self.data)):
                result.append(self.data[i] + other_data[i])
            
        else:  # vertical
            # Check if widths are compatible
            if len(self.data[0]) != len(other_data[0]):
                # If widths are different, resize to the smaller width
                min_width = min(len(self.data[0]), len(other_data[0]))
                for i in range(len(self.data)):
                    self.data[i] = self.data[i][:min_width]
                for i in range(len(other_data)):
                    other_data[i] = other_data[i][:min_width]
            
            # Concatenate vertically
            result = self.data + other_data
        
        self.data = result
