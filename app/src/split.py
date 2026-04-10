import pandas as pd
import yaml
from sklearn.model_selection import train_test_split


PARAMS_PATH = "ml/configs/params.yaml"


def load_params():
    with open(PARAMS_PATH) as f:
        return yaml.safe_load(f)


def main():
    params = load_params()

    input_path = params["dataset"]["features_path"]
    train_path = params["dataset"]["train_path"]
    test_path = params["dataset"]["test_path"]

    test_size = params["dataset"]["test_size"]
    random_state = params["dataset"]["random_state"]

    df = pd.read_csv(input_path)

    train, test = train_test_split(
        df,
        test_size=test_size,
        random_state=random_state,
    )

    train.to_csv(train_path, index=False)
    test.to_csv(test_path, index=False)

    print("Train/test split completed")


if __name__ == "__main__":
    main()