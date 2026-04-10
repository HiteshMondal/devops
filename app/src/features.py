import pandas as pd
import yaml
from pathlib import Path
from sklearn.preprocessing import StandardScaler
from sklearn.preprocessing import OneHotEncoder


PARAMS_PATH = "ml/configs/params.yaml"


def load_params():
    with open(PARAMS_PATH) as f:
        return yaml.safe_load(f)


def main():
    params = load_params()

    input_path = params["dataset"]["processed_path"]
    output_path = params["dataset"]["features_path"]

    df = pd.read_csv(input_path)

    numeric_cols = params["features"]["numeric"]
    categorical_cols = params["features"]["categorical"]

    if numeric_cols:
        scaler = StandardScaler()
        df[numeric_cols] = scaler.fit_transform(df[numeric_cols])

    if categorical_cols:
        encoder = OneHotEncoder(sparse_output=False, handle_unknown="ignore")
        encoded = encoder.fit_transform(df[categorical_cols])

        encoded_df = pd.DataFrame(
            encoded,
            columns=encoder.get_feature_names_out(categorical_cols),
        )

        df = df.drop(columns=categorical_cols)
        df = pd.concat([df, encoded_df], axis=1)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output_path, index=False)

    print(f"Features saved → {output_path}")


if __name__ == "__main__":
    main()